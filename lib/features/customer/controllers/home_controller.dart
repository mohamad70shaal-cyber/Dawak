import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/base/shell_controller.dart';
import '../../../core/services/session_service.dart';
import '../../../data/models/availability.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/order.dart';
import '../../../data/repositories/availability_repository.dart';
import '../../../data/repositories/medicine_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../customer_tabs.dart';

/// Home tab: greeting, category chips and the customer's current orders.
class HomeController extends BaseController {
  HomeController({MedicineRepository? medicines, OrderRepository? orders, AvailabilityRepository? availability, SessionService? session})
      : _medicines = medicines ?? Get.find<MedicineRepository>(),
        _orders = orders ?? Get.find<OrderRepository>(),
        _availability = availability ?? Get.find<AvailabilityRepository>(),
        _session = session ?? Get.find<SessionService>();

  final MedicineRepository _medicines;
  final OrderRepository _orders;
  final AvailabilityRepository _availability;
  final SessionService _session;

  final RxList<MedicineCategory> categories = <MedicineCategory>[].obs;
  final RxList<Order> activeOrders = <Order>[].obs;

  /// "Ask nearby" requests that are still open (shown as a card so the customer can go back to the answers).
  final RxList<AvailabilityRequestSummary> openRequests = <AvailabilityRequestSummary>[].obs;

  DateTime? _loadedAt;
  Worker? _tabWorker;

  String get displayName => _session.profile?.displayName ?? '';

  @override
  void onInit() {
    super.onInit();
    if (Get.isRegistered<ShellController>(tag: ShellTag.customer)) {
      _tabWorker = ever<int>(Get.find<ShellController>(tag: ShellTag.customer).index, (int i) {
        final DateTime? at = _loadedAt;
        if (i == CustomerTabs.home && at != null && DateTime.now().difference(at) > const Duration(seconds: 20)) {
          refreshSilently();
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

  Future<void> reload() => load(_fetch);

  Future<void> refreshSilently() => load(_fetch, silent: true);

  Future<void> _fetch() async {
    final List<List<Object>> r = await Future.wait<List<Object>>(<Future<List<Object>>>[
      _medicines.categories().then((List<MedicineCategory> v) => v.cast<Object>()),
      _orders.myOrders(activeOnly: true, limit: 3).then((List<Order> v) => v.cast<Object>()),
      _openRequestsOrNone().then((List<AvailabilityRequestSummary> v) => v.cast<Object>()),
    ]);
    categories.assignAll(r[0].cast<MedicineCategory>());
    activeOrders.assignAll(r[1].cast<Order>());
    openRequests.assignAll(r[2].cast<AvailabilityRequestSummary>());
    _loadedAt = DateTime.now();
  }

  /// The open requests among the latest few. A failure here must not break the home screen (the card is an extra), so it
  /// reads as "none".
  Future<List<AvailabilityRequestSummary>> _openRequestsOrNone() async {
    try {
      final List<AvailabilityRequestSummary> all = await _availability.mine(limit: 5);
      return all.where((AvailabilityRequestSummary s) => s.status.isOpen).toList();
    } catch (_) {
      return const <AvailabilityRequestSummary>[];
    }
  }
}
