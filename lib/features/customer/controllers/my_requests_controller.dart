import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../data/models/availability.dart';
import '../../../data/repositories/availability_repository.dart';

/// "My requests" (C-30): the customer's "ask nearby" requests, newest first. The server keeps them for 30 days.
class MyRequestsController extends BaseController {
  MyRequestsController({AvailabilityRepository? availability}) : _availability = availability ?? Get.find<AvailabilityRepository>() {
    paged = Paged<AvailabilityRequestSummary>(
      fetch: (int offset, int limit) => _availability.mine(limit: limit, offset: offset),
    );
  }

  final AvailabilityRepository _availability;
  late final Paged<AvailabilityRequestSummary> paged;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    reload();
  }

  Future<void> reload() => paged.reload();

  /// Re-reads the list keeping what is on screen (after a request was closed or the customer came back to the list).
  Future<void> refreshList() => paged.reload(silent: true);
}
