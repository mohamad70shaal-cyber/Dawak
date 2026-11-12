// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/platform.dart';
import 'package:dawak/features/admin/controllers/admin_report_details_controller.dart';
import 'package:dawak/features/admin/controllers/admin_reports_controller.dart';
import 'package:dawak/features/admin/services/admin_dialog_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get_utils/src/extensions/export.dart';

import '../support/harness.dart';
import 'admin_fixtures.dart';

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
    await signInAdmin(h);
    reportRpc(h);
  });
  tearDown(() => h.dispose());

  void seed(List<Map<String, dynamic>> rows) => h.api.tables['user_reports'] = rows;

  group('AdminReportsController', () {
    setUp(() => seed(<Map<String, dynamic>>[
          report('r1', status: 'open', createdAt: '2026-10-10T10:00:00Z'),
          report('r2', status: 'in_review', createdAt: '2026-10-11T10:00:00Z'),
          report('r3', status: 'resolved', createdAt: '2026-10-12T10:00:00Z'),
          report('r4', status: 'dismissed', createdAt: '2026-10-13T10:00:00Z'),
        ]));

    Future<List<String>> ids(AdminReportsController c) async {
      await c.paged.reload();
      return c.paged.items.map((UserReport r) => r.id).toList();
    }

    test('opens on the reports still to do (open and in review), newest first', () async {
      final AdminReportsController c = AdminReportsController();
      expect(c.filter.value, ReportFilter.open);
      expect(await ids(c), <String>['r2', 'r1']);
    });

    test('each filter shows its own statuses', () async {
      final AdminReportsController c = AdminReportsController();
      c.filter.value = ReportFilter.resolved;
      expect(await ids(c), <String>['r3']);
      c.filter.value = ReportFilter.dismissed;
      expect(await ids(c), <String>['r4']);
      c.filter.value = ReportFilter.all;
      expect(await ids(c), <String>['r4', 'r3', 'r2', 'r1']);
    });

    test('the status lists of the filters', () {
      expect(ReportFilter.open.statuses, <String>['open', 'in_review']);
      expect(ReportFilter.resolved.statuses, <String>['resolved']);
      expect(ReportFilter.dismissed.statuses, <String>['dismissed']);
      expect(ReportFilter.all.statuses, isNull);
    });

    test('choosing the active filter again only refreshes', () async {
      final AdminReportsController c = AdminReportsController();
      c.setFilter(ReportFilter.resolved);
      await Future<void>.delayed(Duration.zero);
      final int before = h.api.calls.where((String l) => l == 'select:user_reports').length;
      c.setFilter(ReportFilter.resolved);
      await Future<void>.delayed(Duration.zero);
      expect(h.api.calls.where((String l) => l == 'select:user_reports').length, before + 1);
      expect(c.paged.items.map((UserReport r) => r.id), <String>['r3']);
    });

    test('opening a report goes to its review screen', () async {
      final List<String> routes = <String>[];
      final AdminReportsController c = AdminReportsController(open: (String r) async {
        routes.add(r);
        return null;
      });
      await c.paged.reload();
      await c.openReport(c.paged.items.first);
      expect(routes, <String>[AppRoutes.adminReport('r2')]);
    });

    test('no reports is the empty state', () async {
      seed(<Map<String, dynamic>>[]);
      final AdminReportsController c = AdminReportsController();
      await c.paged.reload();
      expect(c.paged.status.value.name, 'empty');
    });
  });

  group('AdminReportDetailsController', () {
    late List<String> routes;

    setUp(() {
      routes = <String>[];
    });

    Future<AdminReportDetailsController> details(
      String status, {
      AdminReasonFn? ask,
      String target = 'pharmacy',
      String? targetId = 'ph-1',
      String? note,
    }) async {
      seed(<Map<String, dynamic>>[report('r1', status: status, target: target, targetId: targetId, note: note)]);
      final AdminReportDetailsController c = AdminReportDetailsController(
        reportId: 'r1',
        askNote: ask,
        open: (String r) async {
          routes.add(r);
          return null;
        },
      );
      await c.refresh();
      return c;
    }

    test('loads the report', () async {
      final AdminReportDetailsController c = await details('open');
      expect(c.report.value!.category, 'pharmacy_problem');
      expect(c.report.value!.description, 'الصيدلية لا ترد على الهاتف');
    });

    test('a missing report is a failure the screen can show', () async {
      seed(<Map<String, dynamic>>[]);
      final AdminReportDetailsController c = AdminReportDetailsController(reportId: 'nope');
      await c.refresh();
      expect(c.failure.value?.code, 'not_found');
    });

    test('each status offers exactly its own actions', () async {
      final Map<String, Set<String>> expected = <String, Set<String>>{
        'open': <String>{'review', 'resolve', 'dismiss'},
        'in_review': <String>{'resolve', 'dismiss'},
        'resolved': <String>{},
        'dismissed': <String>{},
      };
      for (final MapEntry<String, Set<String>> e in expected.entries) {
        final AdminReportDetailsController c = await details(e.key);
        final Set<String> got = <String>{
          if (c.canStartReview) 'review',
          if (c.canResolve) 'resolve',
          if (c.canDismiss) 'dismiss',
        };
        expect(got, e.value, reason: e.key);
      }
    });

    test('starting the review sends in_review without a note', () async {
      final AdminReportDetailsController c = await details('open');
      expect(await c.startReview(), isTrue);
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_report_id': 'r1', 'p_status': 'in_review', 'p_note': null});
      expect(c.report.value!.status, 'in_review');
      expect(c.canStartReview, isFalse);
      expect(c.canResolve, isTrue);
    });

    test('resolving sends the trimmed note', () async {
      final AdminReportDetailsController c = await details('in_review', ask: reasonIs('  اتصلنا بالصيدلية وأصلحت الرقم  '));
      expect(await c.resolve(), isTrue);
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_report_id': 'r1', 'p_status': 'resolved', 'p_note': 'اتصلنا بالصيدلية وأصلحت الرقم'});
      expect(c.report.value!.status, 'resolved');
      expect(c.report.value!.resolutionNote, 'اتصلنا بالصيدلية وأصلحت الرقم');
      expect(c.canResolve, isFalse);
    });

    test('a note is optional: an empty one is sent as null', () async {
      final AdminReportDetailsController c = await details('open', ask: reasonIs(''));
      expect(await c.dismiss(), isTrue);
      expect(h.api.rpcLog.single.params['p_status'], 'dismissed');
      expect(h.api.rpcLog.single.params['p_note'], isNull);
      expect(c.report.value!.status, 'dismissed');
    });

    test('dismissing the dialog sends nothing', () async {
      final AdminReportDetailsController c = await details('open', ask: reasonIs(null));
      expect(await c.resolve(), isFalse);
      expect(await c.dismiss(), isFalse);
      expect(h.api.rpcCount('admin_resolve_report'), 0);
      expect(c.report.value!.status, 'open');
    });

    test('a closed report cannot be decided again', () async {
      final AdminReportDetailsController c = await details('resolved', ask: reasonIs('x'));
      expect(await c.resolve(), isFalse);
      expect(await c.dismiss(), isFalse);
      expect(await c.startReview(), isFalse);
      expect(h.api.rpcCount('admin_resolve_report'), 0);
    });

    test('a refusal shows a notice and re-reads the report', () async {
      final AdminReportDetailsController c = await details('open');
      h.api.rpcs['admin_resolve_report'] = (Map<String, dynamic> p) => throw const AppFailure('forbidden');
      h.api.tables['user_reports']!.single['status'] = 'resolved';

      expect(await c.startReview(), isFalse);

      expect(c.notice.value, 'err_forbidden'.tr);
      expect(c.report.value!.status, 'resolved', reason: 'the buttons follow the server\'s state');
      expect(c.canResolve, isFalse);
    });

    group('what the report is about', () {
      test('a pharmacy report opens the pharmacy', () async {
        final AdminReportDetailsController c = await details('open', target: 'pharmacy', targetId: 'ph-9');
        expect(c.targetRoute, AppRoutes.adminPharmacy('ph-9'));
        await c.openTarget();
        expect(routes, <String>[AppRoutes.adminPharmacy('ph-9')]);
      });

      test('a medicine report opens the medicine', () async {
        final AdminReportDetailsController c = await details('open', target: 'medicine', targetId: 'm-3');
        expect(c.targetRoute, AppRoutes.adminMedicine('m-3'));
      });

      test('orders, the app and other reports have nothing to open', () async {
        for (final String target in <String>['order', 'app', 'other']) {
          final AdminReportDetailsController c = await details('open', target: target, targetId: 'x-1');
          expect(c.targetRoute, isNull, reason: target);
          await c.openTarget();
        }
        expect(routes, isEmpty);
      });

      test('a report without a target id has nothing to open', () async {
        final AdminReportDetailsController c = await details('open', target: 'pharmacy', targetId: null);
        expect(c.targetRoute, isNull);
      });
    });
  });
}
