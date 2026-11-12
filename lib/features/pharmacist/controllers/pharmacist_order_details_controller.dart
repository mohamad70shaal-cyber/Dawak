import 'dart:async';

import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/order.dart';
import '../../../data/repositories/order_repository.dart';
import '../services/dialog_hooks.dart';
import '../services/pharmacist_refresh.dart';

/// One reservation order as the pharmacy sees it (P-56): accept (P-57), reject with a reason (P-58), mark ready (P-59),
/// cancel an accepted reservation (P-63), reactivate an expired one (P-64), and start the handover (P-61).
///
/// After every refusal the order is re-read, so the buttons always match the server's state (the customer may have
/// cancelled, or the reservation may have expired, while the screen was open).
class PharmacistOrderDetailsController extends BaseController {
  PharmacistOrderDetailsController({
    String? orderId,
    OrderRepository? orders,
    ConfirmFn? confirm,
    ReasonFn? askReason,
    Future<Object?> Function(String route)? open,
    DateTime Function()? clock,
    Duration tickEvery = const Duration(seconds: 30),
  })  : _orderId = orderId,
        _orders = orders ?? Get.find<OrderRepository>(),
        _confirm = confirm ?? defaultConfirm,
        _askReason = askReason ?? defaultReason,
        _open = open ?? ((String r) async=> Get.toNamed<Object?>(r)),
        _clock = clock ?? DateTime.now,
        _tickEvery = tickEvery;

  final String? _orderId;
  final OrderRepository _orders;
  final ConfirmFn _confirm;
  final ReasonFn _askReason;
  final Future<Object?> Function(String route) _open;
  final DateTime Function() _clock;
  final Duration _tickEvery;

  final Rxn<Order> order = Rxn<Order>();
  late final Rx<DateTime> now = _clock().obs;
  final RxnString notice = RxnString();
  Timer? _timer;

  String get id => _orderId ?? Get.parameters['id'] ?? '';

  @override
  void onInit() {
    super.onInit();
    _timer = Timer.periodic(_tickEvery, (Timer _) => tick());
  }

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  /// Advances the clock the countdown is computed from (also called by the periodic timer).
  void tick() => now.value = _clock();

  Duration? get remaining => order.value?.remaining(now: now.value);

  /// True when the reservation time has run out but the server has not swept it yet.
  bool get overdue {
    final Duration? r = remaining;
    return r != null && r.isNegative;
  }

  Future<void> refresh({bool silent = false}) => load(() async {
        final Order? o = await _orders.getOrder(id);
        if (o == null) throw const AppFailure('not_found');
        order.value = o;
        tick();
      }, silent: silent);

  OrderStatus? get state => order.value?.status;

  bool get canAccept => state == OrderStatus.pending;
  bool get canReject => state == OrderStatus.pending;
  bool get canMarkReady => state == OrderStatus.accepted;
  bool get canCancel => state == OrderStatus.accepted || state == OrderStatus.readyForPickup;
  bool get canHandover => state == OrderStatus.readyForPickup;
  bool get canReactivate => state == OrderStatus.expired;

  Future<bool> _run(String successKey, Future<Order> Function() call) async {
    final Order? updated = await submit<Order>(call, toast: false);
    if (updated == null) {
      final AppFailure? f = failure.value;
      notice.value = f == null ? null : _explain(f);
      await refresh(silent: true);
      PharmacistRefresh.ordersChanged();
      return false;
    }
    order.value = updated;
    notice.value = null;
    AppToast.success(successKey.tr);
    PharmacistRefresh.ordersChanged();
    return true;
  }

  String _explain(AppFailure f) {
    switch (f.code) {
      case 'invalid_transition':
        return 'p_order_notice_changed'.tr;
      case 'reservation_expired':
        return 'p_order_notice_expired'.tr;
      default:
        return failureText(f);
    }
  }

  Future<bool> accept() async {
    if (!canAccept || submitting.value) return false;
    final bool ok = await _confirm(
      title: 'p_order_accept_title'.tr,
      message: 'p_order_accept_message'.tr,
      confirmLabel: 'p_order_accept'.tr,
    );
    if (!ok) return false;
    return _run('p_order_accepted', () => _orders.accept(id));
  }

  Future<bool> reject() async {
    if (!canReject || submitting.value) return false;
    final String? reason = await _askReason(
      title: 'p_order_reject_title'.tr,
      label: 'p_order_reject_reason'.tr,
      message: 'p_order_reject_message'.tr,
      confirmLabel: 'p_order_reject'.tr,
      minLength: 3,
      destructive: true,
    );
    if (reason == null) return false;
    return _run('p_order_rejected', () => _orders.reject(id, reason));
  }

  Future<bool> markReady() async {
    if (!canMarkReady || submitting.value) return false;
    return _run('p_order_marked_ready', () => _orders.markReady(id));
  }

  Future<bool> cancel() async {
    if (!canCancel || submitting.value) return false;
    final String? reason = await _askReason(
      title: 'p_order_cancel_title'.tr,
      label: 'p_order_cancel_reason'.tr,
      message: 'p_order_cancel_message'.tr,
      confirmLabel: 'p_order_cancel'.tr,
      minLength: 3,
      destructive: true,
    );
    if (reason == null) return false;
    return _run('p_order_cancelled', () => _orders.cancelByPharmacy(id, reason));
  }

  Future<bool> reactivate() async {
    if (!canReactivate || submitting.value) return false;
    final bool ok = await _confirm(
      title: 'p_order_reactivate_title'.tr,
      message: 'p_order_reactivate_message'.tr,
      confirmLabel: 'p_order_reactivate'.tr,
    );
    if (!ok) return false;
    return _run('p_order_reactivated', () => _orders.reactivate(id));
  }

  Future<void> openHandover() async {
    if (!canHandover) return;
    await _open(AppRoutes.orderHandoverOf(id));
    await refresh(silent: true);
  }
}
