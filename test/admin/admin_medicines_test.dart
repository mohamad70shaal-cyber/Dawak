// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/features/admin/controllers/admin_medicine_editor_controller.dart';
import 'package:dawak/features/admin/controllers/admin_medicines_controller.dart';
import 'package:dawak/features/admin/services/admin_dialog_hooks.dart';
import 'package:flutter/material.dart';
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

  group('AdminMedicinesController', () {
    setUp(() {
      seedMedicines(h, <Map<String, dynamic>>[
        medicine('m1', ar: 'بنادول', en: 'Panadol', createdAt: '2026-10-05T10:00:00Z'),
        medicine('m2', status: 'pending', ar: 'أموكسيل', en: 'Amoxil', createdAt: '2026-10-07T10:00:00Z'),
        medicine('m3', status: 'rejected', ar: 'دواء مرفوض', en: 'Rejected', createdAt: '2026-10-06T10:00:00Z'),
        medicine('m4', status: 'archived', ar: 'دواء قديم', en: 'Old', createdAt: '2026-10-04T10:00:00Z'),
      ]);
    });

    Future<List<String>> ids(AdminMedicinesController c) async {
      await c.paged.reload();
      return c.paged.items.map((Medicine m) => m.id).toList();
    }

    test('by default every entry is listed, newest first', () async {
      final AdminMedicinesController c = AdminMedicinesController();
      expect(c.filter.value, MedicineFilter.all);
      expect(await ids(c), <String>['m2', 'm3', 'm1', 'm4']);
    });

    test('each filter shows its own status', () async {
      final AdminMedicinesController c = AdminMedicinesController();
      c.filter.value = MedicineFilter.pending;
      expect(await ids(c), <String>['m2']);
      c.filter.value = MedicineFilter.approved;
      expect(await ids(c), <String>['m1']);
      c.filter.value = MedicineFilter.rejected;
      expect(await ids(c), <String>['m3']);
      c.filter.value = MedicineFilter.archived;
      expect(await ids(c), <String>['m4']);
    });

    test('searching matches the Arabic and the English name', () async {
      final AdminMedicinesController c = AdminMedicinesController();
      c.search('Amox');
      await Future<void>.delayed(Duration.zero);
      expect(c.paged.items.map((Medicine m) => m.id), <String>['m2']);
      c.search('بنادول');
      await Future<void>.delayed(Duration.zero);
      expect(c.paged.items.map((Medicine m) => m.id), <String>['m1']);
    });

    test('characters that would break the server filter are ignored in the search', () async {
      final AdminMedicinesController c = AdminMedicinesController();
      c.search('Pana,(%)');
      await Future<void>.delayed(Duration.zero);
      expect(c.paged.items.map((Medicine m) => m.id), <String>['m1']);
    });

    test('opening an entry and adding a new one go to the editor', () async {
      final List<String> routes = <String>[];
      final AdminMedicinesController c = AdminMedicinesController(open: (String r) async {
        routes.add(r);
        return null;
      });
      await c.paged.reload();
      await c.openMedicine(c.paged.items.first);
      await c.openNew();
      expect(routes, <String>[AppRoutes.adminMedicine('m2'), AppRoutes.adminMedicineNew]);
    });

    test('choosing the active filter again only refreshes', () async {
      final AdminMedicinesController c = AdminMedicinesController();
      c.setFilter(MedicineFilter.pending);
      await Future<void>.delayed(Duration.zero);
      final int before = h.api.calls.where((String l) => l == 'select:medicines').length;
      c.setFilter(MedicineFilter.pending);
      await Future<void>.delayed(Duration.zero);
      expect(h.api.calls.where((String l) => l == 'select:medicines').length, before + 1);
      expect(c.paged.items.map((Medicine m) => m.id), <String>['m2']);
    });
  });

  group('AdminMedicineEditorController', () {
    late List<Object?> closed;

    setUp(() {
      closed = <Object?>[];
      medicineReviewRpc(h);
      h.api.tables['medicine_categories'] = <Map<String, dynamic>>[
        <String, dynamic>{'id': 'cat-1', 'name_ar': 'مسكنات', 'name_en': 'Painkillers', 'sort_order': 1, 'is_active': true},
        <String, dynamic>{'id': 'cat-2', 'name_ar': 'قديم', 'name_en': null, 'sort_order': 2, 'is_active': false},
      ];
    });

    AdminMedicineEditorController make({String? id, AdminConfirmFn? confirm}) =>
        AdminMedicineEditorController(medicineId: id, confirm: confirm, close: closed.add)..onInit();

    /// The editor validates its form, so a (field-less) Form must be mounted for `currentState`.
    Future<void> mountForm(WidgetTester tester, AdminMedicineEditorController c) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: c.form, child: const SizedBox()))));

    group('creating', () {
      test('without an id it creates and starts ready', () {
        final AdminMedicineEditorController c = make();
        expect(c.isNew, isTrue);
        expect(c.status.value.name, 'ready');
        expect(c.canApprove, isFalse);
        expect(c.canArchive, isFalse);
      });

      testWidgets('a name is required; nothing is sent without one', (WidgetTester tester) async {
        final AdminMedicineEditorController c = make();
        await mountForm(tester, c);
        expect(c.nameRule(''), 'val_required'.tr);
        expect(await c.save(), isFalse);
        expect(h.api.calls.where((String l) => l.startsWith('insert:')), isEmpty);
      });

      test('one name is enough, either language; each is limited to 160 characters', () {
        final AdminMedicineEditorController c = make();
        c.nameEn.text = 'Panadol';
        expect(c.nameRule(''), isNull);
        c.nameEn.clear();
        c.nameAr.text = 'بنادول';
        expect(c.nameRule('بنادول'), isNull);
        expect(c.nameRule('ب' * 161), 'val_too_long'.trParams(<String, String>{'n': '160'}));
      });

      testWidgets('saving adds an approved entry with trimmed fields and closes', (WidgetTester tester) async {
        final AdminMedicineEditorController c = make();
        await mountForm(tester, c);
        c.nameAr.text = '  بنادول  ';
        c.nameEn.text = 'Panadol';
        c.strength.text = '500mg';
        c.dosageForm.text = 'أقراص';
        c.categoryId.value = 'cat-1';

        expect(await c.save(), isTrue);

        final Map<String, dynamic> row = h.api.tables['medicines']!.single;
        expect(row['name_ar'], 'بنادول');
        expect(row['name_en'], 'Panadol');
        expect(row['strength'], '500mg');
        expect(row['brand_name'], isNull, reason: 'blank fields are stored as null');
        expect(row['category_id'], 'cat-1');
        expect(row['catalog_status'], 'approved');
        expect(closed, <Object?>[true]);
      });

      testWidgets('an entry the catalogue already has shows a notice and stays open', (WidgetTester tester) async {
        final AdminMedicineEditorController c = make();
        await mountForm(tester, c);
        c.nameAr.text = 'بنادول';
        h.api.failNext('insert:medicines', const AppFailure('duplicate_request'));

        expect(await c.save(), isFalse);

        expect(c.notice.value, 'a_medicine_duplicate'.tr);
        expect(closed, isEmpty);
        expect(c.nameAr.text, 'بنادول', reason: 'the typed text is not lost');
      });
    });

    group('editing', () {
      setUp(() => seedMedicines(h, <Map<String, dynamic>>[
            medicine('m1', status: 'pending', ar: 'بنادول', en: 'Panadol', category: 'cat-1'),
          ]));

      Future<AdminMedicineEditorController> open({AdminConfirmFn? confirm, String id = 'm1'}) async {
        final AdminMedicineEditorController c = make(id: id, confirm: confirm);
        await c.refresh();
        return c;
      }

      test('loads the entry into the form', () async {
        final AdminMedicineEditorController c = await open();
        expect(c.isNew, isFalse);
        expect(c.nameAr.text, 'بنادول');
        expect(c.nameEn.text, 'Panadol');
        expect(c.strength.text, '500mg');
        expect(c.categoryId.value, 'cat-1');
        expect(c.catalogStatus, 'pending');
        expect(c.isDirty, isFalse);
      });

      test('a missing entry is a failure the screen can show', () async {
        final AdminMedicineEditorController c = make(id: 'nope');
        await c.refresh();
        expect(c.failure.value?.code, 'not_found');
      });

      test('typing changes marks the form as changed; undoing them clears it', () async {
        final AdminMedicineEditorController c = await open();
        c.strength.text = '1000mg';
        expect(c.isDirty, isTrue);
        c.strength.text = '500mg';
        expect(c.isDirty, isFalse);
        c.categoryId.value = 'cat-2';
        expect(c.isDirty, isTrue);
      });

      test('white space around a value is not a change', () async {
        final AdminMedicineEditorController c = await open();
        c.nameAr.text = '  بنادول ';
        expect(c.isDirty, isFalse);
      });

      testWidgets('saving updates the entry, keeps its status and closes', (WidgetTester tester) async {
        final AdminMedicineEditorController c = await open();
        await mountForm(tester, c);
        c.strength.text = '1000mg';

        expect(await c.save(), isTrue);

        final Map<String, dynamic> row = h.api.tables['medicines']!.single;
        expect(row['strength'], '1000mg');
        expect(row['catalog_status'], 'pending', reason: 'saving is not a review decision');
        expect(closed, <Object?>[true]);
      });

      testWidgets('an entry that cannot be updated is reported, not ignored', (WidgetTester tester) async {
        final AdminMedicineEditorController c = await open();
        await mountForm(tester, c);
        h.api.tables['medicines']!.clear();
        expect(await c.save(), isFalse);
        expect(closed, isEmpty);
        expect(c.notice.value, 'err_unknown'.tr);
      });
    });

    group('review', () {
      Future<AdminMedicineEditorController> open(String status, {AdminConfirmFn? confirm}) async {
        seedMedicines(h, <Map<String, dynamic>>[medicine('m1', status: status)]);
        final AdminMedicineEditorController c = make(id: 'm1', confirm: confirm);
        await c.refresh();
        return c;
      }

      test('each status offers exactly its own actions', () async {
        final Map<String, Set<String>> expected = <String, Set<String>>{
          'pending': <String>{'approve', 'reject', 'archive'},
          'approved': <String>{'archive'},
          'rejected': <String>{'archive'},
          'archived': <String>{},
        };
        for (final MapEntry<String, Set<String>> e in expected.entries) {
          final AdminMedicineEditorController c = await open(e.key);
          final Set<String> got = <String>{
            if (c.canApprove) 'approve',
            if (c.canReject) 'reject',
            if (c.canArchive) 'archive',
          };
          expect(got, e.value, reason: e.key);
        }
      });

      testWidgets('approving a proposal sends the decision and shows the new status', (WidgetTester tester) async {
        final AdminMedicineEditorController c = await open('pending');
        await mountForm(tester, c);
        expect(await c.approve(), isTrue);
        expect(h.api.rpcLog.single.params, <String, dynamic>{'p_medicine_id': 'm1', 'p_decision': 'approve'});
        expect(c.catalogStatus, 'approved');
        expect(c.canApprove, isFalse);
        expect(closed, isEmpty, reason: 'the admin stays on the screen');
      });

      testWidgets('edits typed before approving are saved first', (WidgetTester tester) async {
        final AdminMedicineEditorController c = await open('pending');
        await mountForm(tester, c);
        c.nameEn.text = 'Panadol Extra';

        expect(await c.approve(), isTrue);

        expect(h.api.calls.indexOf('update:medicines'), lessThan(h.api.calls.indexOf('rpc:admin_review_medicine')));
        expect(h.api.tables['medicines']!.single['name_en'], 'Panadol Extra');
        expect(c.nameEn.text, 'Panadol Extra');
        expect(c.catalogStatus, 'approved');
      });

      testWidgets('clearing both names stops the approval and sends nothing', (WidgetTester tester) async {
        final AdminMedicineEditorController c = await open('pending');
        await mountForm(tester, c);
        c.nameAr.clear();
        c.nameEn.clear();
        expect(c.hasName, isFalse);
        expect(await c.approve(), isFalse);
        expect(h.api.rpcCount('admin_review_medicine'), 0);
        expect(h.api.calls.where((String l) => l == 'update:medicines'), isEmpty);
      });

      testWidgets('a failed save of the edits sends no decision', (WidgetTester tester) async {
        final AdminMedicineEditorController c = await open('pending');
        await mountForm(tester, c);
        c.nameEn.text = 'Panadol Extra';
        h.api.failNext('update:medicines', const AppFailure('forbidden'));
        expect(await c.approve(), isFalse);
        expect(h.api.rpcCount('admin_review_medicine'), 0);
        expect(c.catalogStatus, 'pending');
      });

      testWidgets('rejecting and archiving ask first; declining sends nothing', (WidgetTester tester) async {
        final AdminMedicineEditorController c = await open('pending', confirm: answer(false));
        await mountForm(tester, c);
        expect(await c.reject(), isFalse);
        expect(await c.archive(), isFalse);
        expect(h.api.rpcCount('admin_review_medicine'), 0);
      });

      testWidgets('rejecting a proposal', (WidgetTester tester) async {
        final AdminMedicineEditorController c = await open('pending', confirm: answer(true));
        await mountForm(tester, c);
        expect(await c.reject(), isTrue);
        expect(h.api.rpcLog.single.params['p_decision'], 'reject');
        expect(c.catalogStatus, 'rejected');
      });

      testWidgets('archiving an approved entry; an archived one is final', (WidgetTester tester) async {
        final AdminMedicineEditorController c = await open('approved', confirm: answer(true));
        await mountForm(tester, c);
        expect(await c.archive(), isTrue);
        expect(c.catalogStatus, 'archived');
        expect(c.canArchive, isFalse);
        expect(await c.archive(), isFalse);
        expect(h.api.rpcCount('admin_review_medicine'), 1);
      });

      testWidgets('a state that changed meanwhile shows a notice and refreshes the status', (WidgetTester tester) async {
        final AdminMedicineEditorController c = await open('pending');
        await mountForm(tester, c);
        h.api.tables['medicines']!.single['catalog_status'] = 'approved';

        expect(await c.approve(), isFalse);

        expect(c.notice.value, 'a_medicine_notice_changed'.tr);
        expect(c.catalogStatus, 'approved');
        expect(c.canApprove, isFalse);
      });

      test('cancelling closes without a result', () async {
        final AdminMedicineEditorController c = await open('pending');
        c.cancel();
        expect(closed, <Object?>[null]);
      });
    });

    test('categories include the switched-off ones, so an entry in one keeps its category', () async {
      final AdminMedicineEditorController c = make();
      await c.loadCategories();
      expect(c.categories.map((MedicineCategory x) => x.id), <String>['cat-1', 'cat-2']);
    });
  });
}
