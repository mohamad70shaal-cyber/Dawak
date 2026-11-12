import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/admin_repository.dart';

/// Which reports the list shows. [open] stands for "open" and "in review" together: everything still to do.
enum ReportFilter {
  open,
  resolved,
  dismissed,
  all;

  /// The statuses to ask for, or null for all of them.
  List<String>? get statuses {
    switch (this) {
      case ReportFilter.open:
        return const <String>['open', 'in_review'];
      case ReportFilter.resolved:
        return const <String>['resolved'];
      case ReportFilter.dismissed:
        return const <String>['dismissed'];
      case ReportFilter.all:
        return null;
    }
  }
}

/// User reports (A-10), newest first. Opening one goes to the review screen (A-11).
class AdminReportsController extends BaseController {
  AdminReportsController({AdminRepository? admin, Future<Object?> Function(String route)? open})
      : _admin = admin ?? Get.find<AdminRepository>(),
        _open = open ?? ((String r) async=> Get.toNamed<Object?>(r)) {
    paged = Paged<UserReport>(
      fetch: (int offset, int limit) => _admin.reports(statuses: filter.value.statuses, limit: limit, offset: offset),
      pageSize: 30,
    );
  }

  final AdminRepository _admin;
  final Future<Object?> Function(String route) _open;

  late final Paged<UserReport> paged;
  final Rx<ReportFilter> filter = ReportFilter.open.obs;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    paged.reload();
  }

  /// Choosing the filter that is already active just re-reads the list (it may be stale).
  void setFilter(ReportFilter f) {
    if (filter.value == f) {
      paged.reload(silent: true);
      return;
    }
    filter.value = f;
    paged.reload();
  }

  Future<void> refreshList() => paged.reload(silent: true);

  Future<void> openReport(UserReport r) async {
    await _open(AppRoutes.adminReport(r.id));
  }
}
