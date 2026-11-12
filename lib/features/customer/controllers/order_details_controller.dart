import 'dart:async';

import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/order.dart';
import '../../../data/repositories/order_repository.dart';
import '../services/customer_refresh.dart';

/// One step of the tracking timeline.
class TrackStep {
  const TrackStep({required this.labelKey, required this.time, required this.done, this.negative = false, this.current = false});

  final String labelKey;
  final DateTime? time;
  final bool done;

  /// Rejected / cancelled / expired.
  final bool negative;
  final bool current;
}

/// Order details (C-20), tracking (C-22) and cancellation (C-23). One instance per order (`tag: orderId`).
class OrderDetailsController extends BaseController {
  OrderDetailsController(this.orderId, {OrderRepository? orders, this.tickEvery = const Duration(seconds: 30)})
      : _orders = orders ?? Get.find<OrderRepository>();

  final String orderId;
  final OrderRepository _orders;
  final Duration tickEvery;

  final Rxn<Order> order = Rxn<Order>();

  /// Bumped by a timer so the reservation countdown redraws.
  final RxInt tick = 0.obs;
  Timer? _timer;
  bool _expiryRefreshed = false;

  @override
  void onReady() {
    super.onReady();
    reload();
    _timer = Timer.periodic(tickEvery, (Timer _) {
      tick.value++;
      final Duration? left = remaining;
      if (left != null && left.isNegative && !_expiryRefreshed) {
        _expiryRefreshed = true;
        refreshSilently();
      }
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  Future<void> reload() => load(_fetch);

  Future<void> refreshSilently() => load(_fetch, silent: true);

  Future<void> _fetch() async {
    final Order? o = await _orders.getOrder(orderId);
    if (o == null) throw const AppFailure('not_found');
    order.value = o;
  }

  /// Time left on the pharmacy's promise to hold the order; null when it is not holding it.
  Duration? get remaining {
    final int _ = tick.value; // makes observers redraw when the timer fires
    return order.value?.remaining();
  }

  bool get canCancel => order.value?.customerCanCancel ?? false;

  /// Cancels the order (reason optional). Returns true when the server confirmed. Afterwards the order and the
  /// visible lists are re-read, also when the server refused (the order may have changed meanwhile).
  Future<bool> cancel({String? reason}) async {
    if (submitting.value) return false;
    final Order? updated = await submit<Order>(() => _orders.cancelByCustomer(orderId, reason: reason));
    if (updated == null) {
      await refreshSilently();
      CustomerRefresh.ordersChanged();
      return false;
    }
    order.value = updated;
    CustomerRefresh.ordersChanged();
    return true;
  }

  /// Timeline built from the order's timestamps, oldest first. Active orders end with the steps still to come.
  List<TrackStep> get timeline {
    final Order? o = order.value;
    if (o == null) return const <TrackStep>[];
    final List<({String key, DateTime? at, bool negative})> all = <({String key, DateTime? at, bool negative})>[
      (key: 'c_track_placed', at: o.createdAt, negative: false),
      (key: 'c_track_accepted', at: o.acceptedAt, negative: false),
      (key: 'c_track_ready', at: o.readyAt, negative: false),
      (key: 'c_track_completed', at: o.completedAt, negative: false),
      (key: 'c_track_rejected', at: o.rejectedAt, negative: true),
      (key: 'c_track_cancelled', at: o.cancelledAt, negative: true),
      (key: 'c_track_expired', at: o.expiredAt, negative: true),
    ];
    final List<MapEntry<int, ({String key, DateTime? at, bool negative})>> done = <MapEntry<int, ({String key, DateTime? at, bool negative})>>[
      for (int i = 0; i < all.length; i++)
        if (all[i].at != null) MapEntry<int, ({String key, DateTime? at, bool negative})>(i, all[i]),
    ]..sort((MapEntry<int, ({String key, DateTime? at, bool negative})> a, MapEntry<int, ({String key, DateTime? at, bool negative})> b) {
        final int c = a.value.at!.compareTo(b.value.at!);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final List<TrackStep> steps = <TrackStep>[
      for (final MapEntry<int, ({String key, DateTime? at, bool negative})> e in done)
        TrackStep(labelKey: e.value.key, time: e.value.at, done: true, negative: e.value.negative),
    ];
    final bool active = o.status == OrderStatus.pending || o.status == OrderStatus.accepted || o.status == OrderStatus.readyForPickup;
    if (active) {
      for (final ({String key, DateTime? at, bool negative}) s in all.sublist(1, 4)) {
        if (s.at == null) steps.add(TrackStep(labelKey: s.key, time: null, done: false));
      }
    }
    // Mark the last finished step as the current one.
    final int last = steps.lastIndexWhere((TrackStep s) => s.done);
    if (last >= 0) {
      final TrackStep s = steps[last];
      steps[last] = TrackStep(labelKey: s.labelKey, time: s.time, done: true, negative: s.negative, current: true);
    }
    return steps;
  }
}
