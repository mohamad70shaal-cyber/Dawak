import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../core/services/session_service.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/order.dart';
import '../../../data/repositories/order_repository.dart';

enum OrderTab { fresh, accepted, ready, history, expired }

extension OrderTabInfo on OrderTab {
  List<OrderStatus> get statuses {
    switch (this) {
      case OrderTab.fresh:
        return const <OrderStatus>[OrderStatus.pending];
      case OrderTab.accepted:
        return const <OrderStatus>[OrderStatus.accepted];
      case OrderTab.ready:
        return const <OrderStatus>[OrderStatus.readyForPickup];
      case OrderTab.history:
        return const <OrderStatus>[OrderStatus.completed, OrderStatus.rejected, OrderStatus.cancelled];
      case OrderTab.expired:
        return const <OrderStatus>[OrderStatus.expired];
    }
  }

  String get labelKey => 'p_orders_tab_$name';
}

/// Orders of the pharmacy in five tabs (P-55, with the expired tab P-64). Opening the screen first asks the server to
/// sweep expired reservations, so the "expired" tab reflects reality.
class PharmacistOrdersController extends BaseController {
  PharmacistOrdersController({OrderRepository? orders, SessionService? session, Future<Object?> Function(String route)? open})
      : _orders = orders ?? Get.find<OrderRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _open = open ?? ((String r) async=> Get.toNamed<Object?>(r)) {
    for (final OrderTab t in OrderTab.values) {
      _pages[t] = Paged<Order>(
        fetch: (int offset, int limit) => _orders.pharmacyOrders(pharmacyId, statuses: t.statuses, limit: limit, offset: offset),
        pageSize: 20,
      );
    }
  }

  final OrderRepository _orders;
  final SessionService _session;
  final Future<Object?> Function(String route) _open;
  final Map<OrderTab, Paged<Order>> _pages = <OrderTab, Paged<Order>>{};

  String get pharmacyId => _session.pharmacy?.id ?? '';

  Paged<Order> pageFor(OrderTab t) => _pages[t]!;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    refreshAll();
  }

  /// Sweeps expired reservations (best effort), then reloads every tab.
  Future<void> refreshAll({bool silent = false}) async {
    try {
      await _orders.expireReservations(pharmacyId);
    } catch (_) {
      // The lists still load; expiry is also applied when an order is opened or acted on.
    }
    await Future.wait<void>(<Future<void>>[for (final Paged<Order> p in _pages.values) p.reload(silent: silent)]);
  }

  Future<void> refreshTab(OrderTab t) => pageFor(t).reload(silent: true);

  Future<void> openOrder(Order o) async {
    await _open(AppRoutes.pharmacistOrder(o.id));
    await refreshAll(silent: true);
  }
}
