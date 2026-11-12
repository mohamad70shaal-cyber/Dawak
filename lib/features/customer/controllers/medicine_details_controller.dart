import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/idempotency.dart';
import '../../../data/models/availability.dart';
import '../../../data/models/geo.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/availability_repository.dart';
import '../../../data/repositories/medicine_repository.dart';
import '../services/customer_dialog_hooks.dart';
import 'cart_controller.dart';
import 'customer_location.dart';

/// Shows the "ask nearby" explanation only once per app run (the customer has understood it after the first time).
class AskNearbyIntro {
  const AskNearbyIntro._();

  static bool seen = false;
}

/// Medicine details (C-13) and the pharmacies that say they have it (C-14). Both screens share one instance per medicine
/// (registered with `tag: medicineId`).
///
/// Pharmacies are listed nearest first when the customer's position is known, otherwise the most recently confirmed first.
/// A pharmacy's word is all there is — no stock is counted — so every offer shows when it was last confirmed. When the
/// list is empty, or the customer wants a fresh answer, [askNearby] asks the pharmacies around.
class MedicineDetailsController extends BaseController {
  MedicineDetailsController(
    this.medicineId, {
    MedicineRepository? medicines,
    AvailabilityRepository? availability,
    CartController? cart,
    CustomerLocation? location,
    CustomerConfirmFn? confirm,
    void Function(String route)? open,
    this.locateGrace = const Duration(seconds: 2),
  })  : _medicines = medicines ?? Get.find<MedicineRepository>(),
        _availability = availability ?? Get.find<AvailabilityRepository>(),
        cart = cart ?? Get.find<CartController>(),
        where = location ?? CustomerLocation(),
        _confirm = confirm ?? defaultCustomerConfirm,
        _open = open ?? ((String route) => Get.toNamed<dynamic>(route)) {
    offers = Paged<MedicineOffer>(fetch: _fetchOffers);
  }

  final String medicineId;
  final MedicineRepository _medicines;
  final AvailabilityRepository _availability;
  final CartController cart;
  final CustomerLocation where;
  final CustomerConfirmFn _confirm;
  final void Function(String route) _open;

  /// How long the first load waits for the GPS before it shows the list without distances (it then reloads by itself).
  final Duration locateGrace;

  late final Paged<MedicineOffer> offers;

  final Rxn<Medicine> medicine = Rxn<Medicine>();

  final IdempotencyKeeper _keeper = IdempotencyKeeper();
  bool _offersRequested = false;
  GeoPoint? _usedPoint;

  @override
  void onReady() {
    super.onReady();
    reload();
  }

  Future<void> reload() => load(() async {
        final Medicine? m = await _medicines.getById(medicineId);
        if (m == null) throw const AppFailure('not_found');
        medicine.value = m;
      });

  // ---- the pharmacies that have it -------------------------------------------------------------------------

  Future<List<MedicineOffer>> _fetchOffers(int offset, int limit) {
    // Later pages must use the position of the first page, or the order would change between pages.
    final GeoPoint? near = offset == 0 ? where.point.value : _usedPoint;
    if (offset == 0) _usedPoint = near;
    return _medicines.offers(medicineId, near: near, limit: limit, offset: offset);
  }

  /// True when the list on screen was sorted by distance.
  bool get located => _usedPoint != null;

  /// Loads the first page of offers the first time the pharmacies screen opens; later calls only refresh when [force].
  /// The position is asked for at the same time: when it arrives in time the list is distance-sorted at once, otherwise
  /// the list appears first and is re-read as soon as the position is known.
  Future<void> ensureOffers({bool force = false}) async {
    if (_offersRequested && !force) return;
    _offersRequested = true;
    final Future<GeoPoint?> position = where.locate();
    await position.timeout(locateGrace, onTimeout: () => null);
    await offers.reload();
    final GeoPoint? p = await position.timeout(const Duration(seconds: 15), onTimeout: () => null);
    if (p != null && _usedPoint == null) await offers.reload(silent: true);
  }

  /// "Use my location" (after a refusal or for a fresh fix): re-reads the list sorted by distance.
  Future<void> useMyLocation() async {
    final GeoPoint? p = await where.locate(forceFresh: true);
    if (p != null) await offers.reload();
  }

  // ---- reserve ---------------------------------------------------------------------------------------------

  /// The cart line for an offer. The medicine is the one of this screen.
  CartLine lineForOffer(MedicineOffer o) => CartLine.fromOffer(o, medicine.value ?? Medicine(id: medicineId), quantity: 1);

  CartPharmacy targetForOffer(MedicineOffer o) => CartPharmacy(id: o.pharmacy.id, name: o.pharmacy.name, currency: o.currency);

  // ---- ask nearby ------------------------------------------------------------------------------------------

  /// True while the position is being read or the request is being created.
  bool get starting => where.locating.value || submitting.value;

  /// "Ask the pharmacies nearby": explains once what happens, reads the position, creates the request and opens its screen.
  /// Returns the request's id, or null when the customer declined, the position could not be read (see
  /// [CustomerLocation.error]) or the server refused (the failure is toasted).
  Future<String?> askNearby() async {
    if (starting) return null;
    if (!AskNearbyIntro.seen) {
      final bool ok = await _confirm(
        title: 'c_ask_intro_title'.tr,
        message: 'c_ask_intro_message'.tr,
        confirmLabel: 'c_ask_intro_confirm'.tr,
      );
      if (!ok) return null;
      AskNearbyIntro.seen = true;
    }
    final GeoPoint? from = await where.locate();
    if (from == null) return null;
    // The same medicine from the same spot is the same request: a retry after a lost answer must not create a second one.
    final String signature = '$medicineId|${from.latitude.toStringAsFixed(4)}|${from.longitude.toStringAsFixed(4)}';
    final String key = _keeper.keyFor(signature, 'ask');
    final AvailabilityRequest? r = await submit<AvailabilityRequest>(
      () => _availability.create(medicineId: medicineId, from: from, idempotencyKey: key),
    );
    if (r == null) return null;
    _keeper.clear();
    _open(AppRoutes.customerRequest(r.id));
    return r.id;
  }
}
