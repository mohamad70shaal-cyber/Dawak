// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/datasources/api_client.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/data/models/platform.dart';
import 'package:dawak/features/admin/controllers/admin_pharmacies_controller.dart';
import 'package:dawak/features/admin/controllers/admin_pharmacy_details_controller.dart';
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
    addProfile(h, 'owner-1', name: 'أحمد الصالح', phone: '+963944000111');
    addProfile(h, 'owner-2', name: 'سلمى حداد');
  });
  tearDown(() => h.dispose());

  group('AdminPharmaciesController', () {
    setUp(() {
      seedPharmacies(h, <Map<String, dynamic>>[
        pharmacy('ph-1', status: 'pending', name: 'صيدلية الشفاء', submittedAt: '2026-10-10T10:00:00Z'),
        pharmacy('ph-2', status: 'pending', owner: 'owner-2', name: 'صيدلية النور', submittedAt: '2026-10-12T10:00:00Z'),
        pharmacy('ph-3', status: 'approved', name: 'صيدلية الأمل'),
        pharmacy('ph-4', status: 'suspended', name: 'صيدلية السلام'),
        pharmacy('ph-5', status: 'rejected', name: 'صيدلية الفجر'),
      ]);
    });

    Future<List<String>> ids(AdminPharmaciesController c) async {
      await c.paged.reload();
      return c.paged.items.map((PharmacyApplication a) => a.pharmacy.id).toList();
    }

    test('opens on the applications waiting for review, newest first', () async {
      final AdminPharmaciesController c = AdminPharmaciesController();
      expect(c.filter.value, PharmacyFilter.pending);
      expect(await ids(c), <String>['ph-2', 'ph-1']);
    });

    test('each filter shows its own status; "all" shows every one', () async {
      final AdminPharmaciesController c = AdminPharmaciesController();
      c.filter.value = PharmacyFilter.approved;
      expect(await ids(c), <String>['ph-3']);
      c.filter.value = PharmacyFilter.suspended;
      expect(await ids(c), <String>['ph-4']);
      c.filter.value = PharmacyFilter.rejected;
      expect(await ids(c), <String>['ph-5']);
      c.filter.value = PharmacyFilter.all;
      expect((await ids(c)).toSet(), <String>{'ph-1', 'ph-2', 'ph-3', 'ph-4', 'ph-5'});
    });

    test('setFilter reloads; choosing the same filter again only refreshes', () async {
      final AdminPharmaciesController c = AdminPharmaciesController();
      await c.paged.reload();
      c.setFilter(PharmacyFilter.approved);
      await Future<void>.delayed(Duration.zero);
      expect(c.paged.items.map((PharmacyApplication a) => a.pharmacy.id), <String>['ph-3']);

      final int before = h.api.calls.where((String l) => l == 'select:pharmacies').length;
      c.setFilter(PharmacyFilter.approved);
      await Future<void>.delayed(Duration.zero);
      expect(c.filter.value, PharmacyFilter.approved);
      expect(h.api.calls.where((String l) => l == 'select:pharmacies').length, before + 1, reason: 're-read once, stale lists are not kept');
    });

    test('each row carries its owner\'s name and phone', () async {
      final AdminPharmaciesController c = AdminPharmaciesController();
      await c.paged.reload();
      final PharmacyApplication first = c.paged.items.firstWhere((PharmacyApplication a) => a.pharmacy.id == 'ph-1');
      expect(first.ownerName, 'أحمد الصالح');
      expect(first.ownerPhone, '+963944000111');
      final PharmacyApplication second = c.paged.items.firstWhere((PharmacyApplication a) => a.pharmacy.id == 'ph-2');
      expect(second.ownerName, 'سلمى حداد');
    });

    test('searching narrows the list by name', () async {
      final AdminPharmaciesController c = AdminPharmaciesController();
      c.setFilter(PharmacyFilter.all);
      c.search('النور');
      await Future<void>.delayed(Duration.zero);
      expect(c.paged.items.map((PharmacyApplication a) => a.pharmacy.id), <String>['ph-2']);
    });

    test('characters that would break the server filter are ignored in the search', () async {
      final AdminPharmaciesController c = AdminPharmaciesController();
      c.setFilter(PharmacyFilter.all);
      c.search('النور,(%)');
      await Future<void>.delayed(Duration.zero);
      expect(c.paged.items.map((PharmacyApplication a) => a.pharmacy.id), <String>['ph-2']);
    });

    test('an empty result is the empty state, not an error', () async {
      seedPharmacies(h, <Map<String, dynamic>>[]);
      final AdminPharmaciesController c = AdminPharmaciesController();
      await c.paged.reload();
      expect(c.paged.items, isEmpty);
      expect(c.paged.failure.value, isNull);
    });

    test('opening a pharmacy goes to its details', () async {
      final List<String> routes = <String>[];
      final AdminPharmaciesController c = AdminPharmaciesController(open: (String r) async {
        routes.add(r);
        return null;
      });
      await c.paged.reload();
      await c.openDetails(c.paged.items.first);
      expect(routes, <String>[AppRoutes.adminPharmacy('ph-2')]);
    });

    test('a failing list is an error the screen can retry', () async {
      h.api.failNext('select:pharmacies', const AppFailure('network'));
      final AdminPharmaciesController c = AdminPharmaciesController();
      await c.paged.reload();
      expect(c.paged.failure.value?.code, 'network');
      await c.paged.reload();
      expect(c.paged.items, isNotEmpty);
    });

    test('more than one page: the next page is appended', () async {
      seedPharmacies(h, <Map<String, dynamic>>[
        for (int i = 0; i < 35; i++) pharmacy('ph-$i', name: 'صيدلية $i', submittedAt: '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}T10:00:00Z'),
      ]);
      final AdminPharmaciesController c = AdminPharmaciesController();
      await c.paged.reload();
      expect(c.paged.items, hasLength(30));
      expect(c.paged.hasMore.value, isTrue);
      await c.paged.loadMore();
      expect(c.paged.items, hasLength(35));
      expect(c.paged.hasMore.value, isFalse);
    });
  });

  group('AdminPharmacyDetailsController', () {
    late List<String> opened;
    bool openResult = true;

    setUp(() {
      opened = <String>[];
      openResult = true;
      pharmacyReviewRpc(h);
    });

    Future<AdminPharmacyDetailsController> details(
      String status, {
      AdminConfirmFn? confirm,
      AdminReasonFn? ask,
      String? license = 'owner-1/license.pdf',
      String? reason,
    }) async {
      seedPharmacies(h, <Map<String, dynamic>>[pharmacy('ph-1', status: status, license: license, reason: reason)]);
      final AdminPharmacyDetailsController c = AdminPharmacyDetailsController(
        pharmacyId: 'ph-1',
        confirm: confirm,
        askReason: ask,
        openUrl: (String url) async {
          opened.add(url);
          return openResult;
        },
      );
      await c.refresh();
      return c;
    }

    test('loads the pharmacy with its owner', () async {
      final AdminPharmacyDetailsController c = await details('pending');
      expect(c.pharmacy!.name, 'صيدلية الشفاء');
      expect(c.application.value!.ownerName, 'أحمد الصالح');
      expect(c.application.value!.ownerPhone, '+963944000111');
    });

    test('a missing pharmacy is a failure the screen can show', () async {
      seedPharmacies(h, <Map<String, dynamic>>[]);
      final AdminPharmacyDetailsController c = AdminPharmacyDetailsController(pharmacyId: 'nope');
      await c.refresh();
      expect(c.failure.value?.code, 'not_found');
    });

    test('each status offers exactly its own actions', () async {
      final Map<String, Set<String>> expected = <String, Set<String>>{
        'pending': <String>{'approve', 'reject'},
        'approved': <String>{'suspend'},
        'suspended': <String>{'reinstate'},
        'rejected': <String>{},
      };
      for (final MapEntry<String, Set<String>> e in expected.entries) {
        final AdminPharmacyDetailsController c = await details(e.key);
        final Set<String> got = <String>{
          if (c.canApprove) 'approve',
          if (c.canReject) 'reject',
          if (c.canSuspend) 'suspend',
          if (c.canReinstate) 'reinstate',
        };
        expect(got, e.value, reason: e.key);
      }
    });

    group('approving', () {
      test('asks first; declining sends nothing', () async {
        final AdminPharmacyDetailsController c = await details('pending', confirm: answer(false));
        expect(await c.approve(), isFalse);
        expect(h.api.rpcCount('admin_review_pharmacy'), 0);
      });

      test('sends the decision without a reason and shows the new status', () async {
        final AdminPharmacyDetailsController c = await details('pending', confirm: answer(true));
        expect(await c.approve(), isTrue);
        expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_decision': 'approve', 'p_reason': null});
        expect(c.state, ApprovalStatus.approved);
        expect(c.canApprove, isFalse);
        expect(c.canSuspend, isTrue);
        expect(c.notice.value, isNull);
      });

      test('is not offered for an approved pharmacy', () async {
        final AdminPharmacyDetailsController c = await details('approved', confirm: answer(true));
        expect(await c.approve(), isFalse);
        expect(h.api.rpcCount('admin_review_pharmacy'), 0);
      });
    });

    group('rejecting', () {
      test('needs a reason: dismissing the dialog sends nothing', () async {
        final AdminPharmacyDetailsController c = await details('pending', ask: reasonIs(null));
        expect(await c.reject(), isFalse);
        expect(h.api.rpcCount('admin_review_pharmacy'), 0);
        expect(c.state, ApprovalStatus.pending);
      });

      test('sends the reason and the owner is shown it', () async {
        final AdminPharmacyDetailsController c = await details('pending', ask: reasonIs('الترخيص منتهي'));
        expect(await c.reject(), isTrue);
        expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_decision': 'reject', 'p_reason': 'الترخيص منتهي'});
        expect(c.state, ApprovalStatus.rejected);
        expect(c.pharmacy!.statusReason, 'الترخيص منتهي');
      });
    });

    group('suspending and reinstating', () {
      test('suspending sends the reason', () async {
        final AdminPharmacyDetailsController c = await details('approved', ask: reasonIs('شكاوى متكررة'));
        expect(await c.suspend(), isTrue);
        expect(h.api.rpcLog.single.params['p_decision'], 'suspend');
        expect(h.api.rpcLog.single.params['p_reason'], 'شكاوى متكررة');
        expect(c.state, ApprovalStatus.suspended);
        expect(c.pharmacy!.isListed, isFalse);
      });

      test('suspending is not possible for a pending application', () async {
        final AdminPharmacyDetailsController c = await details('pending', ask: reasonIs('x'));
        expect(await c.suspend(), isFalse);
        expect(h.api.rpcCount('admin_review_pharmacy'), 0);
      });

      test('reinstating asks first and clears the reason', () async {
        final AdminPharmacyDetailsController c = await details('suspended', confirm: answer(true), reason: 'شكاوى');
        expect(await c.reinstate(), isTrue);
        expect(c.state, ApprovalStatus.approved);
        expect(c.pharmacy!.statusReason, isNull);
        expect(c.pharmacy!.isListed, isTrue);
      });

      test('declining the reinstatement sends nothing', () async {
        final AdminPharmacyDetailsController c = await details('suspended', confirm: answer(false));
        expect(await c.reinstate(), isFalse);
        expect(h.api.rpcCount('admin_review_pharmacy'), 0);
      });
    });

    group('when the server refuses', () {
      test('a state that changed meanwhile shows a notice and the buttons match the new state', () async {
        final AdminPharmacyDetailsController c = await details('pending', confirm: answer(true));
        // Another administrator approved it while this screen was open.
        h.api.tables['pharmacies']!.single['approval_status'] = 'approved';

        expect(await c.approve(), isFalse);

        expect(c.notice.value, 'a_pharmacy_notice_changed'.tr);
        expect(c.state, ApprovalStatus.approved);
        expect(c.canApprove, isFalse);
        expect(c.canSuspend, isTrue);
      });

      test('any other failure keeps the screen and shows its message', () async {
        final AdminPharmacyDetailsController c = await details('pending', confirm: answer(true));
        h.api.rpcs['admin_review_pharmacy'] = (Map<String, dynamic> p) => throw const AppFailure('forbidden');
        expect(await c.approve(), isFalse);
        expect(c.notice.value, 'err_forbidden'.tr);
        expect(c.state, ApprovalStatus.pending);
      });

      test('a successful action clears an older notice', () async {
        final AdminPharmacyDetailsController c = await details('pending', confirm: answer(true));
        c.notice.value = 'old';
        expect(await c.approve(), isTrue);
        expect(c.notice.value, isNull);
      });
    });

    group('the licence document', () {
      test('opens through a signed link for the stored path', () async {
        final AdminPharmacyDetailsController c = await details('pending');
        expect(c.hasLicense, isTrue);
        expect(await c.viewLicense(), isTrue);
        expect(opened, <String>['https://files.test/owner-1/license.pdf']);
      });

      test('a pharmacy without a document has nothing to open', () async {
        final AdminPharmacyDetailsController c = await details('pending', license: null);
        expect(c.hasLicense, isFalse);
        expect(await c.viewLicense(), isFalse);
        expect(opened, isEmpty);
      });

      test('a link that cannot be opened is reported as false and leaves the screen usable', () async {
        final AdminPharmacyDetailsController c = await details('pending');
        openResult = false;
        expect(await c.viewLicense(), isFalse);
        expect(c.submitting.value, isFalse);
      });

      test('a storage failure gives false and the failure', () async {
        final AdminPharmacyDetailsController c = await details('pending');
        final AdminPharmacyDetailsController again = AdminPharmacyDetailsController(
          pharmacyId: 'ph-1',
          files: _FailingFiles(),
          openUrl: (String url) async => true,
        );
        await again.refresh();
        expect(await again.viewLicense(), isFalse);
        expect(again.failure.value?.code, 'storage_failed');
      });
    });
  });
}

class _FailingFiles implements FileStore {
  @override
  Future<String> uploadLicense({required String userId, required String fileName, required List<int> bytes, required String contentType}) async => '';

  @override
  Future<String> signedLicenseUrl(String path, {Duration expiresIn = const Duration(minutes: 10)}) async => throw const AppFailure('storage_failed');
}
