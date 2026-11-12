import 'dart:async';

import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/availability.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/availability_repository.dart';
import '../services/customer_dialog_hooks.dart';
import '../services/customer_refresh.dart';
import 'cart_controller.dart';

/// What the results screen tells the customer, in one word. Decided only from what the server sent.
enum RequestPhase {
  /// Open, nobody has said yes yet: pharmacies are being asked (the server widens the circle by itself).
  waiting,

  /// Open and at least one pharmacy said "available".
  hasOffers,

  /// Open at the largest radius and not a single pharmacy is in range.
  nobodyInRange,

  /// Open at the largest radius, every pharmacy answered and every answer was "unavailable".
  allSaidNo,

  /// The request ran out of time (offers received before are still shown).
  expired,

  /// The customer closed it.
  closed,
}

/// "Ask the pharmacies nearby" results (C-29): one instance per request (`tag: requestId`).
///
/// The server does the work (asks the pharmacies within 1 km, widens to 3 → 5 → 10 km when the circle is empty, everybody
/// said no, or three minutes passed without an answer) and re-evaluates on every read, so this controller only *reads*
/// every [pollEvery] while the request is open. A failed read never replaces what is on screen: the last answer stays and
/// [offline] says it may be old. Polling stops as soon as the request is closed or expired.
class AvailabilityRequestController extends BaseController {
  AvailabilityRequestController(
    this.requestId, {
    AvailabilityRepository? availability,
    CartController? cart,
    CustomerConfirmFn? confirm,
    void Function(String route)? open,
    this.pollEvery = const Duration(seconds: 5),
  })  : _availability = availability ?? Get.find<AvailabilityRepository>(),
        cart = cart ?? Get.find<CartController>(),
        _confirm = confirm ?? defaultCustomerConfirm,
        _open = open ?? ((String route) => Get.toNamed<dynamic>(route));

  final String requestId;
  final AvailabilityRepository _availability;
  final CartController cart;
  final CustomerConfirmFn _confirm;
  final void Function(String route) _open;
  final Duration pollEvery;

  final Rxn<AvailabilityRequest> request = Rxn<AvailabilityRequest>();

  /// True after a read failed (no connection …) and not yet succeeded again: what is on screen may be out of date.
  final RxBool offline = false.obs;

  /// The radius the server widened the search to by itself since the customer opened the screen; null = nothing to say.
  final RxnDouble grewTo = RxnDouble();

  Timer? _timer;
  bool _polling = false;
  DateTime _fetchedAt = DateTime.now();

  /// Bumped by every write (expand / close) so a read that started before it cannot put an older state on screen.
  int _generation = 0;

  @override
  void onReady() {
    super.onReady();
    reload();
  }

  @override
  void onClose() {
    _stopPolling();
    super.onClose();
  }

  Future<void> reload() => load(_fetch);

  Future<void> refreshSilently() => load(_fetch, silent: true);

  Future<void> _fetch() async {
    final int gen = _generation;
    final AvailabilityRequest r = await _availability.get(requestId);
    if (gen != _generation) return;
    _apply(r, announce: false);
  }

  // ---- polling -----------------------------------------------------------------------------------------------

  void _apply(AvailabilityRequest r, {required bool announce}) {
    final AvailabilityRequest? old = request.value;
    if (announce && old != null && r.radiusKm > old.radiusKm) grewTo.value = r.radiusKm;
    request.value = r;
    _fetchedAt = DateTime.now();
    offline.value = false;
    _syncPolling();
  }

  void _syncPolling() {
    final bool open = request.value?.isOpen ?? false;
    if (open && _timer == null && !isClosed) {
      _timer = Timer.periodic(pollEvery, (Timer _) => poll());
    } else if (!open) {
      _stopPolling();
    }
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// One background read. Never throws and never shows a toast: an unreachable server only sets [offline].
  Future<void> poll() async {
    if (_polling || submitting.value || isClosed || request.value == null) return;
    _polling = true;
    final int gen = _generation;
    try {
      final AvailabilityRequest r = await _availability.get(requestId);
      if (gen != _generation || isClosed) return;
      _apply(r, announce: true);
    } catch (e) {
      if (gen != _generation || isClosed) return;
      final AppFailure f = AppFailure.from(e);
      if (f.code == 'not_found') {
        // Deleted on the server (old request): there is nothing left to poll.
        _stopPolling();
        failure.value = f;
        status.value = ViewStatus.error;
      } else {
        offline.value = true;
      }
      await reportToSession(f);
    } finally {
      _polling = false;
    }
  }

  // ---- what to show --------------------------------------------------------------------------------------------

  RequestPhase get phase {
    final AvailabilityRequest? r = request.value;
    if (r == null) return RequestPhase.waiting;
    switch (r.status) {
      case RequestStatus.closed:
        return RequestPhase.closed;
      case RequestStatus.expired:
        return RequestPhase.expired;
      case RequestStatus.open:
        if (r.hasOffers) return RequestPhase.hasOffers;
        if (r.nobodyInRange) return RequestPhase.nobodyInRange;
        if (r.allSaidNo) return RequestPhase.allSaidNo;
        return RequestPhase.waiting;
    }
  }

  /// Time left before the request expires, counted from the moment of the last read; null when it is not open.
  Duration? get remaining {
    final AvailabilityRequest? r = request.value;
    if (r == null || !r.isOpen) return null;
    final Duration left = Duration(seconds: r.secondsLeft) - DateTime.now().difference(_fetchedAt);
    return left.isNegative ? Duration.zero : left;
  }

  void dismissGrowth() => grewTo.value = null;

  // ---- reserve -------------------------------------------------------------------------------------------------

  /// The cart line for an answer; null when the pharmacy's list has no row for the medicine (the button is then hidden).
  CartLine? lineFor(AvailabilityOffer o) {
    final AvailabilityRequest? r = request.value;
    if (r == null) return null;
    return CartLine.fromAnswer(o, r.medicine);
  }

  CartPharmacy targetFor(AvailabilityOffer o) => CartPharmacy(id: o.pharmacy.id, name: o.pharmacy.name, currency: o.currency);

  // ---- actions -------------------------------------------------------------------------------------------------

  /// "Search further": widens the circle by one step now instead of waiting for the server to do it. After a refusal
  /// (largest radius already reached, request closed meanwhile) the screen is re-read, because it was out of date.
  Future<bool> expand() async {
    final AvailabilityRequest? r = request.value;
    if (r == null || !r.canSearchFurther || submitting.value) return false;
    _generation++;
    final AvailabilityRequest? updated = await submit<AvailabilityRequest>(() => _availability.expand(requestId));
    if (updated == null) {
      await refreshSilently();
      return false;
    }
    _apply(updated, announce: false);
    grewTo.value = null;
    CustomerRefresh.requestsChanged();
    return true;
  }

  /// Closes the request after a confirmation (the pharmacies stop being asked). Returns true when the server confirmed.
  Future<bool> closeRequest() async {
    final AvailabilityRequest? r = request.value;
    if (r == null || !r.isOpen || submitting.value) return false;
    final bool ok = await _confirm(
      title: 'c_req_close_title'.tr,
      message: 'c_req_close_message'.tr,
      confirmLabel: 'c_req_close_confirm'.tr,
      destructive: true,
    );
    if (!ok) return false;
    _generation++;
    final AvailabilityRequest? updated = await submit<AvailabilityRequest>(() => _availability.close(requestId));
    if (updated == null) {
      await refreshSilently();
      return false;
    }
    _apply(updated, announce: false);
    CustomerRefresh.requestsChanged();
    return true;
  }

  /// Back to the medicine, where "ask nearby" starts a new request (a closed one cannot be reopened).
  void openMedicine() {
    final Medicine? m = request.value?.medicine;
    if (m == null) return;
    _open(AppRoutes.medicine(m.id));
  }

  void openPharmacy(AvailabilityOffer o) => _open(AppRoutes.pharmacy(o.pharmacy.id));
}
