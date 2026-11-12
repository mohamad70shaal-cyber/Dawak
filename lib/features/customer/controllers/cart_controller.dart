import 'package:get/get.dart';

import '../../../core/services/session_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/availability.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/order.dart';
import '../../../data/repositories/medicine_repository.dart';

/// One line of the cart. Immutable: changes replace the line in [CartController.lines].
class CartLine {
  const CartLine({
    required this.productId,
    required this.medicine,
    required this.unitPrice,
    required this.quantity,
    this.freshness = Freshness.recent,
    this.confirmedAt,
    this.unavailable = false,
  });

  final String productId;
  final Medicine medicine;

  /// The price the customer saw (sent as `expected_unit_price`).
  final double unitPrice;
  final int quantity;

  /// How recently the pharmacy confirmed this medicine when the customer added it.
  final Freshness freshness;
  final DateTime? confirmedAt;

  /// Set by a server revalidation when the pharmacy no longer lists the medicine as available.
  final bool unavailable;

  double get lineTotal => roundMoney(unitPrice * quantity);

  CartLine copyWith({
    Medicine? medicine,
    double? unitPrice,
    int? quantity,
    Freshness? freshness,
    DateTime? confirmedAt,
    bool? unavailable,
  }) =>
      CartLine(
        productId: productId,
        medicine: medicine ?? this.medicine,
        unitPrice: unitPrice ?? this.unitPrice,
        quantity: quantity ?? this.quantity,
        freshness: freshness ?? this.freshness,
        confirmedAt: confirmedAt ?? this.confirmedAt,
        unavailable: unavailable ?? this.unavailable,
      );

  factory CartLine.fromProduct(PublicProduct p, {int quantity = 1}) => CartLine(
        productId: p.productId,
        medicine: p.medicine,
        unitPrice: p.price,
        quantity: quantity,
        freshness: p.freshness,
        confirmedAt: p.confirmedAt,
      );

  factory CartLine.fromOffer(MedicineOffer o, Medicine medicine, {int quantity = 1}) => CartLine(
        productId: o.productId,
        medicine: medicine,
        unitPrice: o.price,
        quantity: quantity,
        freshness: o.freshness,
        confirmedAt: o.confirmedAt,
      );

  /// A pharmacy's live answer "available at this price" as a cart line. Null when the pharmacy's list has no row for the
  /// medicine any more (nothing to reserve). The answer is new, so the line counts as recently confirmed.
  static CartLine? fromAnswer(AvailabilityOffer o, Medicine medicine, {int quantity = 1}) {
    final String? id = o.productId;
    if (id == null || id.isEmpty) return null;
    return CartLine(
      productId: id,
      medicine: medicine,
      unitPrice: o.price,
      quantity: quantity,
      freshness: Freshness.recent,
      confirmedAt: o.answeredAt,
    );
  }
}

/// The pharmacy the cart belongs to.
class CartPharmacy {
  const CartPharmacy({required this.id, required this.name, required this.currency});

  final String id;
  final String name;
  final String currency;
}

enum CartAddResult { added, increased, needsReplace, maxReached, cartFull }

/// What a server revalidation found.
class CartSyncResult {
  const CartSyncResult({this.priceChanged = 0, this.unavailable = 0});

  final int priceChanged;

  /// Lines the pharmacy no longer lists as available.
  final int unavailable;

  bool get hasChanges => priceChanged > 0 || unavailable > 0;
}

/// The customer's cart: lines of ONE pharmacy, kept in memory for the app session (permanent controller). There is no
/// stock: the cart only asks the pharmacy to hold the medicines, and the pharmacy confirms (or not) when it accepts.
/// Cleared on sign-out and, by the checkout, only after the server confirmed the order.
class CartController extends GetxController {
  CartController({MedicineRepository? medicines, SessionService? session})
      : _medicines = medicines ?? Get.find<MedicineRepository>(),
        _session = session ?? (Get.isRegistered<SessionService>() ? Get.find<SessionService>() : null);

  /// `max_customer_qty_per_item` and `max_order_lines` of the server.
  static const int maxQtyPerLine = 10;
  static const int maxLines = 20;

  static const int _catalogueLimit = 50;
  static const int _catalogueMaxPages = 20;

  final MedicineRepository _medicines;
  final SessionService? _session;

  final Rxn<CartPharmacy> pharmacy = Rxn<CartPharmacy>();
  final RxList<CartLine> lines = <CartLine>[].obs;

  /// The order the server confirmed last (read by the result screen; transient, not persisted).
  final Rxn<Order> lastPlaced = Rxn<Order>();

  /// Outcome of the latest successful revalidation (the cart screen explains changes from it).
  final Rxn<CartSyncResult> lastSync = Rxn<CartSyncResult>();

  final RxBool revalidating = false.obs;
  final RxBool syncFailed = false.obs;

  Worker? _sessionWorker;

  @override
  void onInit() {
    super.onInit();
    final SessionService? s = _session;
    if (s != null) {
      _sessionWorker = ever(s.state, (dynamic snap) {
        if (!s.signedIn) {
          clear();
          lastPlaced.value = null;
        }
      });
    }
  }

  @override
  void onClose() {
    _sessionWorker?.dispose();
    super.onClose();
  }

  bool get isEmpty => lines.isEmpty;

  int get itemCount => lines.fold<int>(0, (int s, CartLine l) => s + l.quantity);

  double get total => roundMoney(lines.fold<double>(0, (double s, CartLine l) => s + l.lineTotal));

  String get currency => pharmacy.value?.currency ?? 'SYP';

  bool get hasUnavailable => lines.any((CartLine l) => l.unavailable);

  bool get canCheckout => lines.isNotEmpty && !hasUnavailable && pharmacy.value != null;

  CartLine? lineFor(String productId) {
    for (final CartLine l in lines) {
      if (l.productId == productId) return l;
    }
    return null;
  }

  /// Adds one unit (or [line.quantity]). A cart holds one pharmacy: from another pharmacy this returns
  /// [CartAddResult.needsReplace] and changes nothing; the UI asks and then calls [replaceWith].
  CartAddResult add(CartPharmacy target, CartLine line) {
    final CartPharmacy? current = pharmacy.value;
    if (current != null && lines.isNotEmpty && current.id != target.id) return CartAddResult.needsReplace;
    final int i = lines.indexWhere((CartLine l) => l.productId == line.productId);
    if (i < 0 && lines.length >= maxLines) return CartAddResult.cartFull;
    pharmacy.value = target;
    if (i < 0) {
      lines.add(line.copyWith(quantity: line.quantity.clamp(1, maxQtyPerLine)));
      return CartAddResult.added;
    }
    final CartLine existing = lines[i];
    if (existing.quantity >= maxQtyPerLine) return CartAddResult.maxReached;
    lines[i] = existing.copyWith(
      quantity: (existing.quantity + line.quantity).clamp(1, maxQtyPerLine),
      unitPrice: line.unitPrice,
      freshness: line.freshness,
      confirmedAt: line.confirmedAt,
      unavailable: false,
    );
    return CartAddResult.increased;
  }

  /// Empties the cart and starts a new one at [target].
  CartAddResult replaceWith(CartPharmacy target, CartLine line) {
    clear();
    return add(target, line);
  }

  /// Sets a quantity within 1..[maxQtyPerLine] (a value below 1 removes the line).
  void setQuantity(String productId, int quantity) {
    final int i = lines.indexWhere((CartLine l) => l.productId == productId);
    if (i < 0) return;
    if (quantity < 1) {
      remove(productId);
      return;
    }
    lines[i] = lines[i].copyWith(quantity: quantity > maxQtyPerLine ? maxQtyPerLine : quantity);
  }

  void remove(String productId) {
    lines.removeWhere((CartLine l) => l.productId == productId);
    if (lines.isEmpty) pharmacy.value = null;
  }

  void clear() {
    lines.clear();
    pharmacy.value = null;
    syncFailed.value = false;
    lastSync.value = null;
  }

  /// Called by the checkout after the server confirmed [order].
  void completeOrder(Order order) {
    lastPlaced.value = order;
    clear();
  }

  /// Re-reads the pharmacy's public list and updates the price and freshness of every line. Lines the pharmacy no longer
  /// lists as available are flagged, never silently removed. Returns null when the server could not be reached (the
  /// local cart stays as it is).
  Future<CartSyncResult?> revalidate() async {
    final CartPharmacy? ph = pharmacy.value;
    if (ph == null || lines.isEmpty || revalidating.value) return const CartSyncResult();
    revalidating.value = true;
    syncFailed.value = false;
    try {
      final Set<String> wanted = lines.map((CartLine l) => l.productId).toSet();
      final Map<String, PublicProduct> found = <String, PublicProduct>{};
      for (int page = 0; page < _catalogueMaxPages && found.length < wanted.length; page++) {
        final List<PublicProduct> items =
            await _medicines.pharmacyCatalogue(ph.id, limit: _catalogueLimit, offset: page * _catalogueLimit);
        for (final PublicProduct p in items) {
          if (wanted.contains(p.productId)) found[p.productId] = p;
        }
        if (items.length < _catalogueLimit) break;
      }
      int priceChanged = 0;
      int unavailable = 0;
      final List<CartLine> next = <CartLine>[];
      for (final CartLine l in lines) {
        final PublicProduct? p = found[l.productId];
        if (p == null) {
          unavailable++;
          next.add(l.copyWith(unavailable: true));
          continue;
        }
        if ((p.price - l.unitPrice).abs() > 0.004) priceChanged++;
        next.add(l.copyWith(
          unitPrice: p.price,
          freshness: p.freshness,
          confirmedAt: p.confirmedAt,
          medicine: p.medicine,
          unavailable: false,
        ));
      }
      lines.assignAll(next);
      final CartSyncResult result = CartSyncResult(priceChanged: priceChanged, unavailable: unavailable);
      lastSync.value = result;
      return result;
    } catch (_) {
      // The local cart stays usable; the cart screen shows a notice and a retry.
      syncFailed.value = true;
      return null;
    } finally {
      revalidating.value = false;
    }
  }

  /// Order lines in the shape `create_order` expects, with the prices the customer saw.
  List<OrderLineInput> toInputs() => lines
      .map((CartLine l) => OrderLineInput(productId: l.productId, quantity: l.quantity, expectedUnitPrice: l.unitPrice))
      .toList();
}
