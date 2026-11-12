// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/data/models/platform.dart';
import 'package:dawak/features/admin/controllers/admin_account_controller.dart';
import 'package:dawak/features/admin/controllers/admin_audit_logs_controller.dart';
import 'package:dawak/features/admin/controllers/admin_users_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get_utils/src/extensions/export.dart';

import '../support/harness.dart';
import 'admin_fixtures.dart';

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
    await signInAdmin(h);
  });
  tearDown(() => h.dispose());

  group('AdminUsersController', () {
    setUp(() {
      addProfile(h, 'p1', name: 'أحمد الصيدلاني', phone: '+963944111111');
      addProfile(h, 'p2', name: 'سلمى', status: 'suspended', reason: 'شكاوى');
      addProfile(h, 'a2', role: 'admin', name: 'مشرف آخر');
      addProfile(h, 'c1', role: 'customer', name: 'زبون');
      h.api.rpcs['admin_set_account_status'] = (Map<String, dynamic> p) {
        final Map<String, dynamic> row = h.api.tables['profiles']!.firstWhere((Map<String, dynamic> r) => r['id'] == p['p_user_id']);
        row['account_status'] = p['p_status'];
        row['suspended_reason'] = p['p_status'] == 'suspended' ? p['p_reason'] : null;
        return <String, dynamic>{'id': row['id'], 'account_status': row['account_status']};
      };
    });

    Future<List<String>> ids(AdminUsersController c) async {
      await c.paged.reload();
      return c.paged.items.map((AccountSummary a) => a.id).toSet().toList()..sort();
    }

    AccountSummary byId(AdminUsersController c, String id) => c.paged.items.firstWhere((AccountSummary a) => a.id == id);

    test('lists pharmacists and admins, never customers', () async {
      final AdminUsersController c = AdminUsersController(confirm: answer(true), askReason: reasonIs('x'));
      expect(await ids(c), <String>['a2', 'admin-1', 'p1', 'p2']);
    });

    test('the role chips narrow the list', () async {
      final AdminUsersController c = AdminUsersController();
      c.role.value = AccountRoleFilter.pharmacist;
      expect(await ids(c), <String>['p1', 'p2']);
      c.role.value = AccountRoleFilter.admin;
      expect(await ids(c), <String>['a2', 'admin-1']);
    });

    test('a customer can never be listed, whatever the filter', () async {
      final AdminUsersController c = AdminUsersController();
      for (final AccountRoleFilter f in AccountRoleFilter.values) {
        c.role.value = f;
        expect(await ids(c), isNot(contains('c1')), reason: f.name);
      }
    });

    test('searching by name or by phone', () async {
      final AdminUsersController c = AdminUsersController();
      c.search('سلمى');
      await Future<void>.delayed(Duration.zero);
      expect(c.paged.items.map((AccountSummary a) => a.id), <String>['p2']);
      c.search('944111');
      await Future<void>.delayed(Duration.zero);
      expect(c.paged.items.map((AccountSummary a) => a.id), <String>['p1']);
    });

    test('characters that would break the server filter are ignored in the search', () async {
      final AdminUsersController c = AdminUsersController();
      c.search('سلمى,(%)');
      await Future<void>.delayed(Duration.zero);
      expect(c.paged.items.map((AccountSummary a) => a.id), <String>['p2']);
    });

    test('choosing the active role again does nothing', () async {
      final AdminUsersController c = AdminUsersController();
      await c.paged.reload();
      final int before = h.api.calls.where((String l) => l == 'select:profiles').length;
      c.setRole(AccountRoleFilter.all);
      await Future<void>.delayed(Duration.zero);
      expect(h.api.calls.where((String l) => l == 'select:profiles').length, before);
    });

    group('who can be changed', () {
      test('pharmacists yes; admins and the signed-in admin themselves no', () async {
        final AdminUsersController c = AdminUsersController();
        await c.paged.reload();
        expect(c.myId, 'admin-1');
        expect(c.canChange(byId(c, 'p1')), isTrue);
        expect(c.canChange(byId(c, 'p2')), isTrue);
        expect(c.canChange(byId(c, 'a2')), isFalse);
        expect(c.canChange(byId(c, 'admin-1')), isFalse);
      });

      test('an action on an account that cannot be changed sends nothing', () async {
        final AdminUsersController c = AdminUsersController(confirm: answer(true), askReason: reasonIs('x'));
        await c.paged.reload();
        expect(await c.suspend(byId(c, 'a2')), isFalse);
        expect(await c.suspend(byId(c, 'admin-1')), isFalse);
        expect(h.api.rpcCount('admin_set_account_status'), 0);
      });
    });

    group('suspending', () {
      test('needs a reason: dismissing the dialog sends nothing', () async {
        final AdminUsersController c = AdminUsersController(askReason: reasonIs(null));
        await c.paged.reload();
        expect(await c.suspend(byId(c, 'p1')), isFalse);
        expect(h.api.rpcCount('admin_set_account_status'), 0);
      });

      test('sends the reason and the list shows the new state', () async {
        final AdminUsersController c = AdminUsersController(askReason: reasonIs('مخالفة الشروط'));
        await c.paged.reload();
        expect(await c.suspend(byId(c, 'p1')), isTrue);
        expect(h.api.rpcLog.single.params, <String, dynamic>{'p_user_id': 'p1', 'p_status': 'suspended', 'p_reason': 'مخالفة الشروط'});
        expect(byId(c, 'p1').suspended, isTrue);
        expect(byId(c, 'p1').suspendedReason, 'مخالفة الشروط');
      });

      test('an account that is suspended already is not suspended twice', () async {
        final AdminUsersController c = AdminUsersController(askReason: reasonIs('x'));
        await c.paged.reload();
        expect(await c.suspend(byId(c, 'p2')), isFalse);
        expect(h.api.rpcCount('admin_set_account_status'), 0);
      });

      test('a refusal is reported and the list is re-read', () async {
        final AdminUsersController c = AdminUsersController(askReason: reasonIs('x'));
        await c.paged.reload();
        h.api.rpcs['admin_set_account_status'] = (Map<String, dynamic> p) => throw const AppFailure('forbidden');
        expect(await c.suspend(byId(c, 'p1')), isFalse);
        expect(c.failure.value?.code, 'forbidden');
        expect(byId(c, 'p1').suspended, isFalse);
      });
    });

    group('reactivating', () {
      test('asks first; declining sends nothing', () async {
        final AdminUsersController c = AdminUsersController(confirm: answer(false));
        await c.paged.reload();
        expect(await c.reactivate(byId(c, 'p2')), isFalse);
        expect(h.api.rpcCount('admin_set_account_status'), 0);
      });

      test('sends the status without a reason and clears the stored one', () async {
        final AdminUsersController c = AdminUsersController(confirm: answer(true));
        await c.paged.reload();
        expect(await c.reactivate(byId(c, 'p2')), isTrue);
        expect(h.api.rpcLog.single.params, <String, dynamic>{'p_user_id': 'p2', 'p_status': 'active', 'p_reason': null});
        expect(byId(c, 'p2').suspended, isFalse);
        expect(byId(c, 'p2').suspendedReason, isNull);
      });

      test('an active account has nothing to reactivate', () async {
        final AdminUsersController c = AdminUsersController(confirm: answer(true));
        await c.paged.reload();
        expect(await c.reactivate(byId(c, 'p1')), isFalse);
        expect(h.api.rpcCount('admin_set_account_status'), 0);
      });
    });

    test('roles are what the database says', () async {
      final AdminUsersController c = AdminUsersController();
      await c.paged.reload();
      expect(byId(c, 'p1').role, UserRole.pharmacist);
      expect(byId(c, 'a2').role, UserRole.admin);
    });
  });

  group('AdminAuditLogsController', () {
    Map<String, dynamic> entry(String id, String action, {String? actor = 'admin-1', String at = '2026-10-12T10:00:00Z', Map<String, dynamic>? details}) => <String, dynamic>{
          'id': id,
          'actor_id': actor,
          'action': action,
          'entity_type': 'pharmacy',
          'entity_id': 'ph-1234567890',
          'pharmacy_id': 'ph-1',
          'details': details ?? <String, dynamic>{},
          'created_at': at,
        };

    setUp(() {
      addProfile(h, 'p1', name: 'أحمد الصيدلاني');
      h.api.tables['audit_logs'] = <Map<String, dynamic>>[
        entry('e1', 'pharmacy_approve', at: '2026-10-10T10:00:00Z'),
        entry('e2', 'pharmacy_reject', at: '2026-10-11T10:00:00Z', details: <String, dynamic>{'reason': 'الترخيص منتهي'}),
        entry('e3', 'account_suspended', at: '2026-10-12T10:00:00Z'),
        entry('e4', 'medicine_approve', at: '2026-10-13T10:00:00Z', actor: null),
        entry('e5', 'product_added', at: '2026-10-14T10:00:00Z', actor: 'p1'),
        entry('e6', 'report_resolved', at: '2026-10-15T10:00:00Z', actor: 'customer-unknown'),
      ];
    });

    Future<List<String>> ids(AdminAuditLogsController c) async {
      await c.paged.reload();
      return c.paged.items.map((AuditLogEntry e) => e.id).toList();
    }

    test('lists every entry, newest first', () async {
      final AdminAuditLogsController c = AdminAuditLogsController();
      expect(await ids(c), <String>['e6', 'e5', 'e4', 'e3', 'e2', 'e1']);
    });

    test('each group shows its own actions', () async {
      final AdminAuditLogsController c = AdminAuditLogsController();
      c.group.value = AuditGroup.pharmacies;
      expect(await ids(c), <String>['e2', 'e1']);
      c.group.value = AuditGroup.accounts;
      expect(await ids(c), <String>['e3']);
      c.group.value = AuditGroup.catalogue;
      expect(await ids(c), <String>['e4']);
      c.group.value = AuditGroup.reports;
      expect(await ids(c), <String>['e6']);
      c.group.value = AuditGroup.inventory;
      expect(await ids(c), <String>['e5']);
    });

    test('the groups cover every action the database writes, and each action is in one group only', () {
      const List<String> written = <String>[
        'pharmacy_registered', 'pharmacy_resubmitted', 'pharmacy_updated', 'pharmacy_approve', 'pharmacy_reject', 'pharmacy_suspend',
        'pharmacy_reinstate', 'account_suspended', 'account_active', 'medicine_approve', 'medicine_reject', 'medicine_archive',
        'report_in_review', 'report_resolved', 'report_dismissed', 'product_added', 'product_updated', 'listing_confirmed',
        'products_imported', 'sale_discount',
      ];
      final List<String> grouped = <String>[
        for (final AuditGroup g in AuditGroup.values) ...?g.actions,
      ];
      expect(grouped.toSet(), written.toSet());
      expect(grouped.length, grouped.toSet().length, reason: 'no action in two groups');
    });

    test('every listed action has a translation in both languages', () {
      for (final AuditGroup g in AuditGroup.values) {
        for (final String action in g.actions ?? <String>[]) {
          expect('a_audit_$action'.tr, isNot('a_audit_$action'), reason: action);
        }
      }
    });

    test('names of the people behind the entries are looked up once', () async {
      final AdminAuditLogsController c = AdminAuditLogsController();
      await c.paged.reload();
      final AuditLogEntry byAdmin = c.paged.items.firstWhere((AuditLogEntry e) => e.id == 'e1');
      final AuditLogEntry byPharmacist = c.paged.items.firstWhere((AuditLogEntry e) => e.id == 'e5');
      expect(c.actorName(byAdmin), 'Test admin-1');
      expect(c.actorName(byPharmacist), 'أحمد الصيدلاني');
      final int lookups = h.api.calls.where((String l) => l == 'select:profiles').length;
      await c.paged.reload();
      expect(h.api.calls.where((String l) => l == 'select:profiles').length, lookups, reason: 'known names are not asked for again');
    });

    test('an entry whose actor is unknown or invisible has no name', () async {
      final AdminAuditLogsController c = AdminAuditLogsController();
      await c.paged.reload();
      final AuditLogEntry system = c.paged.items.firstWhere((AuditLogEntry e) => e.id == 'e4');
      final AuditLogEntry customer = c.paged.items.firstWhere((AuditLogEntry e) => e.id == 'e6');
      expect(c.actorName(system), '');
      expect(c.actorName(customer), '');
    });

    test('a failing name lookup does not fail the list', () async {
      final AdminAuditLogsController c = AdminAuditLogsController();
      h.api.failNext('select:profiles', const AppFailure('network'));
      await c.paged.reload();
      expect(c.paged.items, hasLength(6));
      expect(c.paged.failure.value, isNull);
    });

    test('the reason of an entry is shown when it has one', () async {
      final AdminAuditLogsController c = AdminAuditLogsController();
      await c.paged.reload();
      expect(c.reasonOf(c.paged.items.firstWhere((AuditLogEntry e) => e.id == 'e2')), 'الترخيص منتهي');
      expect(c.reasonOf(c.paged.items.firstWhere((AuditLogEntry e) => e.id == 'e1')), '');
    });

    test('choosing the active group again does nothing', () async {
      final AdminAuditLogsController c = AdminAuditLogsController();
      await c.paged.reload();
      final int before = h.api.calls.where((String l) => l == 'select:audit_logs').length;
      c.setGroup(AuditGroup.all);
      await Future<void>.delayed(Duration.zero);
      expect(h.api.calls.where((String l) => l == 'select:audit_logs').length, before);
    });

    test('a non-admin gets nothing: the database refuses the read', () async {
      h.api.failNext('select:audit_logs', const AppFailure('forbidden'));
      final AdminAuditLogsController c = AdminAuditLogsController();
      await c.paged.reload();
      expect(c.paged.failure.value?.code, 'forbidden');
    });
  });

  group('AdminAccountController', () {
    test('shows who is signed in', () {
      final AdminAccountController c = AdminAccountController();
      expect(c.name, 'Test admin-1');
      expect(c.email, 'admin-1@test.dev');
    });

    test('toggling the language switches the app and stores it on the profile', () async {
      final AdminAccountController c = AdminAccountController();
      final bool before = c.isArabic;
      await c.toggleLanguage();
      expect(c.isArabic, !before);
      expect(h.api.tables['profiles']!.single['locale'], c.isArabic ? 'ar' : 'en');
    });

    test('signing out ends the session', () async {
      final AdminAccountController c = AdminAccountController();
      await c.signOut();
      expect(h.session.signedIn, isFalse);
    });
  });
}
