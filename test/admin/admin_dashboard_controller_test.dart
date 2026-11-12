// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/base/base_controller.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/platform.dart';
import 'package:dawak/features/admin/controllers/admin_dashboard_controller.dart';
import 'package:dawak/features/admin/controllers/admin_medicines_controller.dart';
import 'package:dawak/features/admin/controllers/admin_pharmacies_controller.dart';
import 'package:dawak/features/admin/controllers/admin_reports_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import 'admin_fixtures.dart';

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
    await signInAdmin(h);
  });
  tearDown(() => h.dispose());

  Map<String, dynamic> metricsJson({int pendingPharmacies = 2, int pendingMedicines = 3, int openReports = 1, int orders = 40, int completed = 30}) =>
      <String, dynamic>{
        'pharmacies': <String, dynamic>{'pending': pendingPharmacies, 'approved': 12, 'rejected': 1, 'suspended': 2},
        'users': <String, dynamic>{'customers': 340, 'pharmacists': 15, 'suspended': 1},
        'medicines': <String, dynamic>{'approved': 900, 'pending': pendingMedicines},
        'orders_30d': <String, dynamic>{'total': orders, 'completed': completed, 'cancelled_or_rejected': 6},
        'sales_30d_count': 210,
        'open_reports': openReports,
      };

  void serve([Map<String, dynamic>? json]) => h.api.rpcs['admin_metrics'] = (Map<String, dynamic> p) => json ?? metricsJson();

  group('loading', () {
    test('reads the aggregate figures from the server', () async {
      serve();
      final AdminDashboardController c = AdminDashboardController();
      await c.refresh();
      expect(c.status.value, ViewStatus.ready);
      final AdminMetrics m = c.metrics.value!;
      expect(m.pendingPharmacies, 2);
      expect(m.approvedPharmacies, 12);
      expect(m.customers, 340);
      expect(m.approvedMedicines, 900);
      expect(m.sales30d, 210);
      expect(h.api.rpcLog.single.fn, 'admin_metrics');
    });

    test('a failure on the first load is an error state; on a refresh the old figures stay', () async {
      h.api.rpcs['admin_metrics'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final AdminDashboardController c = AdminDashboardController();
      await c.refresh();
      expect(c.status.value, ViewStatus.error);
      expect(c.failure.value?.code, 'network');
      expect(c.metrics.value, isNull);

      serve();
      await c.refresh();
      expect(c.metrics.value, isNotNull);
      h.api.rpcs['admin_metrics'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      await c.refresh(silent: true);
      expect(c.metrics.value, isNotNull, reason: 'the figures on screen are kept');
      expect(c.status.value, ViewStatus.ready);
    });

    test('a non-admin is refused by the database and sees an error', () async {
      h.api.rpcs['admin_metrics'] = (Map<String, dynamic> p) => throw const AppFailure('forbidden');
      final AdminDashboardController c = AdminDashboardController();
      await c.refresh();
      expect(c.failure.value?.code, 'forbidden');
    });
  });

  group('what needs attention', () {
    test('adds up applications, proposals and open reports', () async {
      serve();
      final AdminDashboardController c = AdminDashboardController();
      expect(c.needsAttention, 0, reason: 'nothing before the first load');
      await c.refresh();
      expect(c.needsAttention, 6);
    });

    test('is zero when nothing waits', () async {
      serve(metricsJson(pendingPharmacies: 0, pendingMedicines: 0, openReports: 0));
      final AdminDashboardController c = AdminDashboardController();
      await c.refresh();
      expect(c.needsAttention, 0);
    });

    test('completion rate is the share of picked-up reservations, 0 without any', () async {
      serve(metricsJson(orders: 40, completed: 30));
      final AdminDashboardController c = AdminDashboardController();
      await c.refresh();
      expect(c.completionRate, closeTo(0.75, 1e-9));

      serve(metricsJson(orders: 0, completed: 0));
      await c.refresh();
      expect(c.completionRate, 0);
    });
  });

  group('shortcuts', () {
    test('each figure opens its tab with the matching filter', () {
      final List<String> seen = <String>[];
      final AdminDashboardController c = AdminDashboardController(
        showPharmacies: (PharmacyFilter f) => seen.add('pharmacies:${f.name}'),
        showMedicines: (MedicineFilter f) => seen.add('medicines:${f.name}'),
        showReports: (ReportFilter f) => seen.add('reports:${f.name}'),
      );
      c.openPendingPharmacies();
      c.openAllPharmacies();
      c.openSuspendedPharmacies();
      c.openPendingMedicines();
      c.openApprovedMedicines();
      c.openOpenReports();
      expect(seen, <String>[
        'pharmacies:pending',
        'pharmacies:all',
        'pharmacies:suspended',
        'medicines:pending',
        'medicines:approved',
        'reports:open',
      ]);
    });
  });
}
