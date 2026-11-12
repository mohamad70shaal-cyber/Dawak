import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../core/base/shell_controller.dart';
import '../../../data/models/order.dart';
import '../../../data/repositories/order_repository.dart';
import '../customer_tabs.dart';

/// "My orders" tab (C-21): newest first, optionally only active orders.
class CustomerOrdersController extends BaseController {
  CustomerOrdersController({OrderRepository? orders}) : _orders = orders ?? Get.find<OrderRepository>() {
    paged = Paged<Order>(
      fetch: (int offset, int limit) => _orders.myOrders(activeOnly: activeOnly.value, limit: limit, offset: offset),
    );
  }

  final OrderRepository _orders;
  late final Paged<Order> paged;

  /// true = pending / accepted / ready only.
  final RxBool activeOnly = false.obs;

  DateTime? _loadedAt;
  Worker? _tabWorker;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
    if (Get.isRegistered<ShellController>(tag: ShellTag.customer)) {
      _tabWorker = ever<int>(Get.find<ShellController>(tag: ShellTag.customer).index, (int i) {
        final DateTime? at = _loadedAt;
        if (i == CustomerTabs.orders && at != null && DateTime.now().difference(at) > const Duration(seconds: 15)) {
          refreshList();
        }
      });
    }
  }

  @override
  void onReady() {
    super.onReady();
    reload();
  }

  @override
  void onClose() {
    _tabWorker?.dispose();
    super.onClose();
  }

  Future<void> reload() async {
    await paged.reload();
    _loadedAt = DateTime.now();
  }

  /// Re-reads the list keeping what is on screen.
  Future<void> refreshList() async {
    await paged.reload(silent: true);
    _loadedAt = DateTime.now();
  }

  Future<void> setActiveOnly(bool value) async {
    if (activeOnly.value == value) return;
    activeOnly.value = value;
    await reload();
  }
}
