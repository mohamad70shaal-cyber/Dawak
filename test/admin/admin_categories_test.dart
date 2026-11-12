// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/features/admin/controllers/admin_categories_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/harness.dart';
import 'admin_fixtures.dart';

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
    await signInAdmin(h);
    h.api.tables['medicine_categories'] = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'c1', 'name_ar': 'مسكنات', 'name_en': 'Painkillers', 'sort_order': 1, 'is_active': true},
      <String, dynamic>{'id': 'c2', 'name_ar': 'مضادات حيوية', 'name_en': null, 'sort_order': 2, 'is_active': true},
      <String, dynamic>{'id': 'c3', 'name_ar': 'قديم', 'name_en': null, 'sort_order': 3, 'is_active': false},
    ];
  });
  tearDown(() => h.dispose());

  /// The category form validates its fields, so a (field-less) Form must be mounted for `currentState`.
  Future<void> mountForm(WidgetTester tester, AdminCategoriesController c) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: c.form, child: const SizedBox()))));

  List<String> names(AdminCategoriesController c) => c.categories.map((MedicineCategory x) => x.nameAr).toList();

  test('lists every category, the switched-off ones too, in their order', () async {
    final AdminCategoriesController c = AdminCategoriesController();
    await c.refresh();
    expect(names(c), <String>['مسكنات', 'مضادات حيوية', 'قديم']);
    expect(c.categories.last.isActive, isFalse);
  });

  test('no categories is the empty state', () async {
    h.api.tables['medicine_categories'] = <Map<String, dynamic>>[];
    final AdminCategoriesController c = AdminCategoriesController();
    await c.refresh();
    expect(c.status.value.name, 'empty');
  });

  test('a failing load is an error the screen can retry', () async {
    h.api.failNext('select:medicine_categories', const AppFailure('network'));
    final AdminCategoriesController c = AdminCategoriesController();
    await c.refresh();
    expect(c.status.value.name, 'error');
    await c.refresh();
    expect(c.status.value.name, 'ready');
  });

  group('the form', () {
    test('a new category starts blank, active, at the end of the list', () async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      c.nameAr.text = 'old';
      c.startNew();
      expect(c.editing.value, isNull);
      expect(c.nameAr.text, '');
      expect(c.nameEn.text, '');
      expect(c.sortOrder.text, '4');
      expect(c.isActive.value, isTrue);
    });

    test('the first category of an empty list starts at 0', () {
      h.api.tables['medicine_categories'] = <Map<String, dynamic>>[];
      final AdminCategoriesController c = AdminCategoriesController();
      c.startNew();
      expect(c.sortOrder.text, '0');
    });

    test('editing starts from the stored values', () async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      c.startEdit(c.categories.last);
      expect(c.editing.value!.id, 'c3');
      expect(c.nameAr.text, 'قديم');
      expect(c.nameEn.text, '');
      expect(c.sortOrder.text, '3');
      expect(c.isActive.value, isFalse);
    });

    test('field rules: Arabic name required (80 at most), English optional, order a whole number up to 9999', () {
      final AdminCategoriesController c = AdminCategoriesController();
      expect(c.nameArRule(''), isNotNull);
      expect(c.nameArRule('مسكنات'), isNull);
      expect(c.nameArRule('م' * 81), isNotNull);
      expect(c.nameEnRule(''), isNull);
      expect(c.nameEnRule('x' * 81), isNotNull);
      expect(c.sortRule('7'), isNull);
      expect(c.sortRule('abc'), isNotNull);
      expect(c.sortRule('10000'), isNotNull);
      expect(c.sortRule('-1'), isNotNull);
    });
  });

  group('saving', () {
    testWidgets('adds a category with trimmed names and reloads the list', (WidgetTester tester) async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      await mountForm(tester, c);
      c.startNew();
      c.nameAr.text = '  فيتامينات ';
      c.nameEn.text = ' Vitamins ';
      c.sortOrder.text = '٥'; // Arabic-Indic digit

      expect(await c.save(), isTrue);

      final Map<String, dynamic> added = h.api.tables['medicine_categories']!.last;
      expect(added['name_ar'], 'فيتامينات');
      expect(added['name_en'], 'Vitamins');
      expect(added['sort_order'], 5);
      expect(added['is_active'], isTrue);
      expect(names(c), contains('فيتامينات'));
    });

    testWidgets('a blank English name is stored as null', (WidgetTester tester) async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      await mountForm(tester, c);
      c.startNew();
      c.nameAr.text = 'أخرى';
      expect(await c.save(), isTrue);
      expect(h.api.tables['medicine_categories']!.last['name_en'], isNull);
    });

    testWidgets('nothing is sent without an Arabic name', (WidgetTester tester) async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      await mountForm(tester, c);
      c.startNew();
      c.nameEn.text = 'Only English';
      expect(await c.save(), isFalse);
      expect(h.api.calls.where((String l) => l.startsWith('insert:')), isEmpty);
    });

    testWidgets('editing changes the stored row, keeps its id and reloads', (WidgetTester tester) async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      await mountForm(tester, c);
      c.startEdit(c.categories.first);
      c.nameAr.text = 'مسكنات وخافضات الحرارة';
      c.isActive.value = false;

      expect(await c.save(), isTrue);

      final Map<String, dynamic> row = h.api.tables['medicine_categories']!.firstWhere((Map<String, dynamic> r) => r['id'] == 'c1');
      expect(row['name_ar'], 'مسكنات وخافضات الحرارة');
      expect(row['is_active'], isFalse);
      expect(h.api.tables['medicine_categories'], hasLength(3));
      expect(names(c), contains('مسكنات وخافضات الحرارة'));
    });

    testWidgets('a name that exists already shows a notice and keeps the typed text', (WidgetTester tester) async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      await mountForm(tester, c);
      c.startNew();
      c.nameAr.text = 'مسكنات';
      h.api.failNext('insert:medicine_categories', const AppFailure('duplicate_request'));

      expect(await c.save(), isFalse);

      expect(c.notice.value, 'a_category_duplicate'.tr);
      expect(c.nameAr.text, 'مسكنات');
    });

    testWidgets('a category that cannot be updated is reported', (WidgetTester tester) async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      await mountForm(tester, c);
      c.startEdit(c.categories.first);
      h.api.tables['medicine_categories']!.clear();
      expect(await c.save(), isFalse);
      expect(c.notice.value, 'err_unknown'.tr);
    });
  });

  group('switching on and off', () {
    test('toggling flips only is_active and keeps the rest', () async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      expect(await c.toggleActive(c.categories.first), isTrue);
      final Map<String, dynamic> row = h.api.tables['medicine_categories']!.firstWhere((Map<String, dynamic> r) => r['id'] == 'c1');
      expect(row['is_active'], isFalse);
      expect(row['name_ar'], 'مسكنات');
      expect(row['name_en'], 'Painkillers');
      expect(row['sort_order'], 1);
      expect(c.categories.first.isActive, isFalse);
    });

    test('a switched-off category can be switched on again', () async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      expect(await c.toggleActive(c.categories.last), isTrue);
      expect(c.categories.last.isActive, isTrue);
    });

    test('a failure is reported and the list is unchanged', () async {
      final AdminCategoriesController c = AdminCategoriesController();
      await c.refresh();
      h.api.failNext('update:medicine_categories', const AppFailure('forbidden'));
      expect(await c.toggleActive(c.categories.first), isFalse);
      expect(c.categories.first.isActive, isTrue);
      expect(c.failure.value?.code, 'forbidden');
    });
  });
}
