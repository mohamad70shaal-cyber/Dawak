import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/idempotency.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/order.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../services/pharmacist_nav.dart';
import '../services/pharmacist_refresh.dart';

/// One line of the counter basket.
class PosLine {
  const PosLine({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.spec = '',
  });

  final String productId;
  final String name;
  final String spec;
  final double unitPrice;
  final int quantity;

  double get lineTotal => ((unitPrice * quantity) * 100).round() / 100;

  PosLine copyWith({double? unitPrice, int? quantity}) => PosLine(
        productId: productId,
        name: name,
        spec: spec,
        unitPrice: unitPrice ?? this.unitPrice,
        quantity: quantity ?? this.quantity,
      );
}

enum PosAdd { added, atLimit, basketFull }

/// What a re-check of the basket against the server changed.
class PosSyncResult {
  const PosSyncResult({this.removed = 0, this.repriced = 0});

  /// Lines whose medicine is no longer in the pharmacy's list.
  final int removed;

  /// Lines that now have a different price.
  final int repriced;

  bool get changed => removed + repriced > 0;
}

/// Point of sale (P-34 … P-47). Lives as long as the shell, so the basket survives the checkout screens.
///
/// The totals shown here are previews: the server prices the sale and answers with the real invoice. The cashier sells
/// what is on the shelf, so there is no quantity check: a product only has to be in this pharmacy's list. A lost response is safe to retry: the same basket reuses its idempotency key and the server returns the
/// first sale instead of making a second one.
class PosController extends BaseController {
  PosController({
    ListingRepository? listing,
    SalesRepository? sales,
    SessionService? session,
    void Function(Sale sale)? showCompleted,
  })  : _listing = listing ?? Get.find<ListingRepository>(),
        _sales = sales ?? Get.find<SalesRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _showCompleted = showCompleted ?? PharmacistNav.showSaleCompleted {
    products = Paged<PharmacyProduct>(
      fetch: (int offset, int limit) => _listing.sellable(pharmacyId, text: _query, limit: limit, offset: offset),
      pageSize: 30,
    );
  }

  static const int maxLines = 100;
  static const int maxQtyPerLine = 999;

  final ListingRepository _listing;
  final SalesRepository _sales;
  final SessionService _session;
  final void Function(Sale sale) _showCompleted;
  final IdempotencyKeeper _keeper = IdempotencyKeeper();

  late final Paged<PharmacyProduct> products;
  final RxList<PosLine> lines = <PosLine>[].obs;
  final RxDouble discount = 0.0.obs;
  final RxnString discountError = RxnString();

  /// The text field of the discount (owners/managers).
  final TextEditingController discountInput = TextEditingController();

  /// Explains what changed after a server refusal or a re-check, shown above the basket.
  final RxnString notice = RxnString();

  String _query = '';

  String get pharmacyId => _session.pharmacy?.id ?? '';

  String get currency => _session.pharmacy?.currency ?? 'SYP';

  /// Only owners and managers may give a discount.
  bool get canDiscount => _session.snapshot.canManagePharmacy;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    products.reload();
  }

  @override
  void onClose() {
    discountInput.dispose();
    super.onClose();
  }

  // ---- list ---------------------------------------------------------------------------------------------

  void search(String text) {
    final String t = text.trim();
    if (t == _query) return;
    _query = t;
    products.reload();
  }

  Future<void> reloadProducts({bool silent = true}) => products.reload(silent: silent);

  // ---- basket -------------------------------------------------------------------------------------------

  bool get isEmpty => lines.isEmpty;

  int get itemCount => lines.fold<int>(0, (int s, PosLine l) => s + l.quantity);

  double get subtotal => ((lines.fold<double>(0, (double s, PosLine l) => s + l.lineTotal)) * 100).round() / 100;

  double get total => (((subtotal - discount.value) * 100).round() / 100).clamp(0, double.infinity).toDouble();

  int qtyOf(String productId) {
    final int i = lines.indexWhere((PosLine l) => l.productId == productId);
    return i < 0 ? 0 : lines[i].quantity;
  }

  PosAdd add(PharmacyProduct p) {
    final int i = lines.indexWhere((PosLine l) => l.productId == p.id);
    if (i >= 0) {
      if (lines[i].quantity >= maxQtyPerLine) return PosAdd.atLimit;
      lines[i] = lines[i].copyWith(quantity: lines[i].quantity + 1, unitPrice: p.price);
    } else {
      if (lines.length >= maxLines) return PosAdd.basketFull;
      lines.add(PosLine(
        productId: p.id,
        name: p.medicine.displayName(Get.locale?.languageCode != 'en'),
        spec: p.medicine.specLine,
        unitPrice: p.price,
        quantity: 1,
      ));
    }
    _changed();
    return PosAdd.added;
  }

  /// Sets the quantity of a line, at most [maxQtyPerLine]. A quantity below 1 removes the line.
  void setQuantity(String productId, int quantity) {
    final int i = lines.indexWhere((PosLine l) => l.productId == productId);
    if (i < 0) return;
    if (quantity < 1) {
      lines.removeAt(i);
    } else {
      final int q = quantity > maxQtyPerLine ? maxQtyPerLine : quantity;
      lines[i] = lines[i].copyWith(quantity: q);
    }
    _changed();
  }

  void remove(String productId) {
    lines.removeWhere((PosLine l) => l.productId == productId);
    _changed();
  }

  void clear() {
    lines.clear();
    discount.value = 0;
    discountInput.clear();
    discountError.value = null;
    notice.value = null;
    _keeper.clear();
  }

  void _changed() {
    notice.value = null;
    if (discount.value > subtotal) {
      discount.value = subtotal;
      discountInput.text = subtotal > 0 ? _plain(subtotal) : '';
      if (subtotal > 0) notice.value = 'p_pos_discount_adjusted'.tr;
    }
  }

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  // ---- discount -----------------------------------------------------------------------------------------

  /// Applies the discount typed by an owner/manager. Empty text removes it. An invalid text leaves no discount applied
  /// (so a stale amount is never sent) and sets [discountError]. Returns false in that case.
  bool applyDiscount(String text) {
    if (!canDiscount) return false;
    discountError.value = null;
    if (text.trim().isEmpty) {
      discount.value = 0;
      return true;
    }
    final String? problem = Validators.price(text);
    final double? v = Validators.parseDecimal(text);
    if (problem != null || v == null) {
      discount.value = 0;
      discountError.value = problem ?? 'val_number'.tr;
      return false;
    }
    if (v > subtotal) {
      discount.value = 0;
      discountError.value = 'p_pos_discount_too_high'.tr;
      return false;
    }
    discount.value = v;
    return true;
  }

  // ---- server re-check ----------------------------------------------------------------------------------

  /// Re-reads every product of the basket: drops what is no longer in the pharmacy's list and takes the current price. Returns null when the server could not be reached (the basket is left as it is).
  Future<PosSyncResult?> revalidate() async {
    if (lines.isEmpty) return const PosSyncResult();
    final List<PosLine> before = List<PosLine>.of(lines);
    final List<PharmacyProduct?> fresh;
    try {
      fresh = await Future.wait<PharmacyProduct?>(before.map((PosLine l) => _listing.product(l.productId)));
    } catch (_) {
      return null;
    }
    int removed = 0;
    int repriced = 0;
    final List<PosLine> next = <PosLine>[];
    for (int i = 0; i < before.length; i++) {
      final PosLine l = before[i];
      final PharmacyProduct? p = fresh[i];
      if (p == null) {
        removed++;
        continue;
      }
      if (p.price != l.unitPrice) repriced++;
      next.add(l.copyWith(unitPrice: p.price));
    }
    lines.assignAll(next);
    if (discount.value > subtotal) {
      discount.value = subtotal;
      discountInput.text = subtotal > 0 ? _plain(subtotal) : '';
    }
    final PosSyncResult r = PosSyncResult(removed: removed, repriced: repriced);
    notice.value = r.changed ? 'p_pos_notice_changed'.tr : null;
    return r;
  }

  // ---- checkout -----------------------------------------------------------------------------------------

  String _signature() {
    final String items = lines.map((PosLine l) => '${l.productId}:${l.quantity}:${l.unitPrice}').join(',');
    return '$pharmacyId|$items|${discount.value}';
  }

  /// Sends the sale. Returns true when the server confirmed it; the basket is emptied only then.
  Future<bool> checkout() async {
    if (submitting.value || lines.isEmpty) return false;
    notice.value = null;
    final String key = _keeper.keyFor(_signature(), 'pos');
    final Sale? sale = await submit<Sale>(
      () => _sales.createPosSale(
        pharmacyId: pharmacyId,
        items: lines.map((PosLine l) => OrderLineInput(productId: l.productId, quantity: l.quantity, expectedUnitPrice: l.unitPrice)).toList(),
        discount: discount.value,
        idempotencyKey: key,
      ),
      toast: false,
    );
    if (sale == null) {
      await _onFailure(failure.value);
      return false;
    }
    _keeper.clear();
    clear();
    PharmacistRefresh.listChanged();
    _showCompleted(sale);
    return true;
  }

  Future<void> _onFailure(AppFailure? f) async {
    if (f == null) return;
    switch (f.code) {
      case 'product_unavailable':
      case 'price_changed':
        final PosSyncResult? r = await revalidate();
        notice.value = r == null ? failureText(f) : (r.changed ? 'p_pos_notice_changed'.tr : failureText(f));
        PharmacistRefresh.listChanged();
      case 'forbidden':
        // A cashier cannot give discounts: drop it and let the sale be retried without.
        if (discount.value > 0) {
          discount.value = 0;
          discountInput.clear();
          notice.value = 'p_pos_notice_no_discount'.tr;
        } else {
          AppToast.error(failureText(f));
        }
      default:
        notice.value = failureText(f);
    }
  }
}
