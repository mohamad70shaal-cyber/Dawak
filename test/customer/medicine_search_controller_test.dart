// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'dart:async';

import 'package:dawak/core/base/base_controller.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/features/customer/controllers/medicine_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import 'customer_fixtures.dart';

void main() {
  late AppHarness h;
  late MedicineSearchController c;

  setUp(() async {
    h = await AppHarness.create();
    c = MedicineSearchController()..onInit();
  });
  tearDown(() {
    c.onClose();
    h.dispose();
  });

  void serveSearch(List<Map<String, dynamic>> rows) => h.api.rpcs['search_medicines'] = paged(rows);

  group('typing (suggestions)', () {
    test('a single character never reaches the server', () async {
      serveSearch(<Map<String, dynamic>>[searchRow('m1')]);
      await c.onTyping('ب');
      expect(h.api.rpcCount('search_medicines'), 0);
      expect(c.suggestions, isEmpty);
      expect(c.hasQuery, isFalse);
    });

    test('two characters fetch a handful of suggestions', () async {
      serveSearch(<Map<String, dynamic>>[for (int i = 0; i < 10; i++) searchRow('m$i')]);
      await c.onTyping('بن');
      expect(h.api.rpcLog.single.params['p_query'], 'بن');
      expect(h.api.rpcLog.single.params['p_limit'], MedicineSearchController.suggestionCount);
      expect(c.suggestions.length, MedicineSearchController.suggestionCount);
      expect(c.suggesting.value, isFalse);
    });

    test('a slow older answer never overwrites a newer one', () async {
      final Completer<dynamic> slow = Completer<dynamic>();
      h.api.rpcs['search_medicines'] = (Map<String, dynamic> p) {
        if (p['p_query'] == 'بنا') return slow.future;
        return <Map<String, dynamic>>[searchRow('new', ar: 'بنادول جديد')];
      };
      final Future<void> first = c.onTyping('بنا');
      await c.onTyping('بنادول');
      slow.complete(<Map<String, dynamic>>[searchRow('old', ar: 'قديم')]);
      await first;
      expect(c.suggestions.map((Medicine m) => m.id), <String>['new']);
      expect(c.suggesting.value, isFalse);
    });

    test('a failure is kept for the screen and the suggestions are cleared', () async {
      h.api.rpcs['search_medicines'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      await c.onTyping('بنادول');
      expect(c.suggestFailure.value?.code, 'network');
      expect(c.suggestions, isEmpty);
      expect(c.suggesting.value, isFalse);
    });

    test('clearing the text empties suggestions and failure', () async {
      serveSearch(<Map<String, dynamic>>[searchRow('m1')]);
      await c.onTyping('بنادول');
      await c.onTyping('');
      expect(c.suggestions, isEmpty);
      expect(c.suggestFailure.value, isNull);
    });
  });

  group('full search', () {
    test('trims the query, shows it in the box, loads the first page and remembers it', () async {
      serveSearch(<Map<String, dynamic>>[searchRow('m1'), searchRow('m2')]);
      await c.runSearch('  بنادول ');
      expect(c.query.value, 'بنادول');
      expect(c.text.text, 'بنادول');
      expect(c.results.items.map((Medicine m) => m.id), <String>['m1', 'm2']);
      expect(c.results.hasMore.value, isFalse);
      expect(c.recent, <String>['بنادول']);
    });

    test('a too-short query clears the results without calling the server', () async {
      serveSearch(<Map<String, dynamic>>[searchRow('m1')]);
      await c.runSearch('بنادول');
      final int calls = h.api.rpcCount('search_medicines');
      await c.runSearch('ب');
      expect(h.api.rpcCount('search_medicines'), calls);
      expect(c.results.items, isEmpty);
    });

    test('recent searches are de-duplicated, newest first, at most five', () async {
      serveSearch(<Map<String, dynamic>>[]);
      for (final String q in <String>['أ1', 'أ2', 'أ3', 'أ4', 'أ5', 'أ6', 'أ3']) {
        await c.runSearch(q);
      }
      expect(c.recent.length, MedicineSearchController.maxRecent);
      expect(c.recent.first, 'أ3');
      expect(c.recent.where((String r) => r == 'أ3').length, 1);
    });

    test('a full page offers more and loadMore asks for the next offset', () async {
      serveSearch(<Map<String, dynamic>>[for (int i = 0; i < 25; i++) searchRow('m$i')]);
      await c.runSearch('بنادول');
      expect(c.results.items.length, 20);
      expect(c.results.hasMore.value, isTrue);
      await c.results.loadMore();
      expect(h.api.rpcLog.last.params['p_offset'], 20);
      expect(c.results.items.length, 25);
      expect(c.results.hasMore.value, isFalse);
    });

    test('a failing search leaves an error state with the failure code', () async {
      h.api.rpcs['search_medicines'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      await c.runSearch('بنادول');
      expect(c.results.status.value, ViewStatus.error);
      expect(c.results.failure.value?.code, 'network');
    });
  });

  group('filters', () {
    test('applying filters sends category and dosage form and re-runs an active search', () async {
      serveSearch(<Map<String, dynamic>>[searchRow('m1')]);
      await c.runSearch('بنادول');
      c.draftCategoryId.value = 'cat-1';
      c.draftDosageForm.value = 'كبسولة';
      await c.applyFilters();
      final Map<String, dynamic> p = h.api.rpcLog.last.params;
      expect(p['p_category_id'], 'cat-1');
      expect(p['p_dosage_form'], 'كبسولة');
      expect(c.filterCount, 2);
      expect(c.hasFilters, isTrue);
    });

    test('the filter screen starts from the active filters and can be cleared', () {
      c.categoryId.value = 'cat-1';
      c.dosageForm.value = 'شراب';
      c.beginFilterEdit();
      expect(c.draftCategoryId.value, 'cat-1');
      expect(c.draftDosageForm.value, 'شراب');
      c.clearDraft();
      expect(c.draftCategoryId.value, isNull);
      expect(c.draftDosageForm.value, isNull);
      expect(c.categoryId.value, 'cat-1', reason: 'only applying changes the active filters');
    });

    test('removing a filter chip re-runs the search without it', () async {
      serveSearch(<Map<String, dynamic>>[searchRow('m1')]);
      c.categoryId.value = 'cat-1';
      await c.runSearch('بنادول');
      await c.removeCategoryFilter();
      expect(h.api.rpcLog.last.params['p_category_id'], isNull);
      expect(c.categoryId.value, isNull);
    });

    test('dosage form values match what the catalogue stores', () {
      final List<String> values = MedicineSearchController.dosageForms.map((DosageFormOption o) => o.value).toList();
      expect(values, containsAll(<String>['أقراص', 'أقراص فوارة', 'كبسولة', 'شراب', 'بخاخ', 'قطرة']));
      expect(MedicineSearchController.dosageForms.map((DosageFormOption o) => o.id).toSet().length, MedicineSearchController.dosageForms.length);
    });

    test('a category chosen on the home screen becomes an active filter', () async {
      c.applyCategory('cat-9');
      expect(c.categoryId.value, 'cat-9');
      expect(c.draftCategoryId.value, 'cat-9');
    });

    test('route parameters run the search with the category', () async {
      serveSearch(<Map<String, dynamic>>[searchRow('m1')]);
      await c.applyParams(<String, String?>{'q': 'بنادول', 'categoryId': 'cat-2'});
      expect(h.api.rpcLog.last.params['p_query'], 'بنادول');
      expect(h.api.rpcLog.last.params['p_category_id'], 'cat-2');
    });
  });

  group('categories', () {
    test('are loaded once and a failure can be retried', () async {
      h.api.tables['medicine_categories'] = <Map<String, dynamic>>[
        <String, dynamic>{'id': 'cat-1', 'name_ar': 'مسكنات', 'name_en': 'Pain relief', 'sort_order': 1, 'is_active': true},
      ];
      h.api.failNext('select:medicine_categories', const AppFailure('network'));
      expect(c.categoriesLoading.value, isFalse);
      expect(c.categoriesFailed.value, isFalse);
      expect(c.categoriesLoaded.value, isFalse);

      await c.ensureCategories();
      expect(c.categories, isEmpty);
      expect(c.categoriesLoading.value, isFalse);
      expect(c.categoriesFailed.value, isTrue);
      expect(c.categoriesLoaded.value, isFalse);

      expect(await c.reloadCategories(), isTrue);
      expect(c.categories.single.id, 'cat-1');
      expect(c.categoriesLoading.value, isFalse);
      expect(c.categoriesFailed.value, isFalse);
      expect(c.categoriesLoaded.value, isTrue);

      final int selects = h.api.calls.where((String l) => l == 'select:medicine_categories').length;
      await c.ensureCategories();
      expect(h.api.calls.where((String l) => l == 'select:medicine_categories').length, selects, reason: 'already loaded');
      expect(c.categoryName('cat-1', false), 'Pain relief');
      expect(c.categoryName('cat-1', true), 'مسكنات');
      expect(c.categoryName(null, true), '');
    });

    test('concurrent requests share the same in-flight future without duplicate calls', () async {
      h.api.delay = const Duration(milliseconds: 30);
      h.api.tables['medicine_categories'] = <Map<String, dynamic>>[
        <String, dynamic>{'id': 'cat-1', 'name_ar': 'مسكنات', 'name_en': 'Pain relief', 'sort_order': 1, 'is_active': true},
      ];

      final Future<void> req1 = c.ensureCategories();
      expect(c.categoriesLoading.value, isTrue);
      final Future<void> req2 = c.ensureCategories();

      await Future.wait(<Future<void>>[req1, req2]);

      expect(c.categoriesLoading.value, isFalse);
      expect(c.categoriesLoaded.value, isTrue);
      expect(c.categoriesFailed.value, isFalse);
      expect(h.api.calls.where((String l) => l == 'select:medicine_categories').length, 1);
    });

    test('empty category result distinguishes success from failure', () async {
      h.api.tables['medicine_categories'] = <Map<String, dynamic>>[];
      await c.ensureCategories();

      expect(c.categories, isEmpty);
      expect(c.categoriesLoading.value, isFalse);
      expect(c.categoriesLoaded.value, isTrue);
      expect(c.categoriesFailed.value, isFalse);
    });
  });
}
