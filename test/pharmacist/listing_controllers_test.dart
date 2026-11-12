// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/data/repositories/listing_repository.dart';
import 'package:dawak/features/pharmacist/controllers/product_add_controller.dart';
import 'package:dawak/features/pharmacist/controllers/product_details_controller.dart';
import 'package:dawak/features/pharmacist/controllers/product_edit_controller.dart';
import 'package:dawak/features/pharmacist/controllers/products_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import 'pharmacist_fixtures.dart';

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
  });
  tearDown(() => h.dispose());

  /// The controllers validate their form, so a (field-less) Form must be mounted for `form.currentState`.
  Future<void> mount(WidgetTester tester, GlobalKey<FormState> key) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: key, child: const SizedBox()))));

  DateTime daysAgo(int d) => DateTime.now().subtract(Duration(days: d));

  Future<bool> yes({required String title, required String message, String? confirmLabel, bool destructive = false}) async => true;
  Future<bool> no({required String title, required String message, String? confirmLabel, bool destructive = false}) async => false;

  group('the list and its filters', () {
    late ListingRepository repo;

    setUp(() {
      repo = ListingRepository(h.api);
    });

    List<String> ids(List<PharmacyProduct> l) => l.map((PharmacyProduct p) => p.id).toList();

    test('"all" lists every row, available or not; "available" and "unavailable" split them', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('a'), listRow('b', available: false), listRow('c')]);
      expect(ids(await repo.products('ph-1')), <String>['a', 'b', 'c']);
      expect(ids(await repo.products('ph-1', filter: 'available')), <String>['a', 'c']);
      expect(ids(await repo.products('ph-1', filter: 'unavailable')), <String>['b']);
    });

    test('"stale" means available and not confirmed for a week; unavailable rows are never stale', () async {
      seedOrdered(h, <Map<String, dynamic>>[
        listRow('fresh', confirmedAt: daysAgo(2)),
        listRow('old', confirmedAt: daysAgo(PharmacyProduct.freshDays + 1)),
        listRow('old-unavailable', available: false, confirmedAt: daysAgo(30)),
        listRow('edge', confirmedAt: daysAgo(PharmacyProduct.freshDays - 1)),
      ]);
      expect(ids(await repo.products('ph-1', filter: 'stale')), <String>['old']);
    });

    test('only the rows of the given pharmacy are listed', () async {
      final Map<String, dynamic> other = listRow('x');
      other['pharmacy_id'] = 'ph-2';
      seedOrdered(h, <Map<String, dynamic>>[listRow('a'), other]);
      expect(ids(await repo.products('ph-1')), <String>['a']);
    });

    test('offset and limit page through the list', () async {
      seedOrdered(h, <Map<String, dynamic>>[for (int i = 0; i < 7; i++) listRow('p$i')]);
      expect(ids(await repo.products('ph-1', limit: 3, offset: 0)), <String>['p0', 'p1', 'p2']);
      expect(ids(await repo.products('ph-1', limit: 3, offset: 3)), <String>['p3', 'p4', 'p5']);
      expect(ids(await repo.products('ph-1', limit: 3, offset: 6)), <String>['p6']);
      expect(await repo.products('ph-1', limit: 3, offset: 9), isEmpty);
    });

    test('text search matches the medicine names; a category narrows it further', () async {
      seedOrdered(h, <Map<String, dynamic>>[
        listRow('p1', ar: 'بنادول', en: 'Panadol', categoryId: 'cat-pain'),
        listRow('p2', ar: 'أموكسيل', en: 'Amoxil', categoryId: 'cat-abx'),
        listRow('p3', ar: 'بنادول أدفانس', en: 'Panadol Advance', categoryId: 'cat-pain'),
      ]);
      expect(ids(await repo.products('ph-1', text: 'panadol')), <String>['p1', 'p3']);
      expect(ids(await repo.products('ph-1', categoryId: 'cat-abx')), <String>['p2']);
      expect(ids(await repo.products('ph-1', text: 'advance', categoryId: 'cat-pain')), <String>['p3']);
    });

    test('characters that would break the search filter are stripped from the text', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1', en: 'Panadol')]);
      expect(ids(await repo.products('ph-1', text: 'Pana%')), <String>['p1']);
    });

    test('the cashier list ("sellable") includes medicines marked unavailable: the shelf is the truth', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('a'), listRow('b', available: false)]);
      expect(ids(await repo.sellable('ph-1')), <String>['a', 'b']);
    });

    test('product() reads one row with its medicine, or null', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('a', price: 1234, available: false)]);
      final PharmacyProduct? p = await repo.product('a');
      expect(p!.price, 1234);
      expect(p.isAvailable, isFalse);
      expect(p.medicine.nameEn, 'Panadol');
      expect(await repo.product('nope'), isNull);
    });
  });

  group('changing the list (repository)', () {
    late ListingRepository repo;

    setUp(() {
      repo = ListingRepository(h.api);
    });

    test('addProduct sends only the medicine and the price and returns the new id', () async {
      h.api.rpcs['add_pharmacy_product'] = (Map<String, dynamic> p) => <String, dynamic>{'id': 'prod-new'};
      expect(await repo.addProduct(pharmacyId: 'ph-1', medicineId: 'med-1', price: 5500), 'prod-new');
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_medicine_id': 'med-1', 'p_price': 5500});
    });

    test('updateProduct leaves untouched fields null so the server keeps them', () async {
      h.api.rpcs['update_pharmacy_product'] = (Map<String, dynamic> p) => <String, dynamic>{};
      await repo.updateProduct('p1', isAvailable: false);
      expect(h.api.rpcLog.last.params, <String, dynamic>{'p_product_id': 'p1', 'p_price': null, 'p_is_available': false});
      await repo.updateProduct('p1', price: 6000);
      expect(h.api.rpcLog.last.params, <String, dynamic>{'p_product_id': 'p1', 'p_price': 6000, 'p_is_available': null});
      await repo.updateProduct('p1');
      expect(h.api.rpcLog.last.params, <String, dynamic>{'p_product_id': 'p1', 'p_price': null, 'p_is_available': null});
    });

    test('confirmListing returns how many rows were confirmed', () async {
      h.api.rpcs['confirm_listing'] = (Map<String, dynamic> p) => <String, dynamic>{'confirmed': 7};
      expect(await repo.confirmListing('ph-1'), 7);
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1'});
    });

    test('bulkUpsert sends chunks of ${ListingRepository.importChunk} and adds up the results', () async {
      h.api.rpcs['bulk_upsert_pharmacy_products'] = (Map<String, dynamic> p) {
        final int n = (p['p_items'] as List<dynamic>).length;
        return <String, dynamic>{'inserted': n - 1, 'updated': 1, 'skipped': 0};
      };
      final List<ListingEntry> entries = <ListingEntry>[
        for (int i = 0; i < ListingRepository.importChunk * 2 + 10; i++) ListingEntry(medicineId: 'm$i', price: 1000.0 + i),
      ];
      final List<int> progress = <int>[];

      final ImportResult r = await repo.bulkUpsert('ph-1', entries, onProgress: (int done, int total) => progress.add(done));

      expect(h.api.rpcCount('bulk_upsert_pharmacy_products'), 3);
      expect((h.api.rpcLog.first.params['p_items'] as List<dynamic>).length, ListingRepository.importChunk);
      expect((h.api.rpcLog.last.params['p_items'] as List<dynamic>).length, 10);
      expect(h.api.rpcLog.first.params['p_items'].first, <String, dynamic>{'medicine_id': 'm0', 'price': 1000.0});
      expect(r.updated, 3);
      expect(r.inserted, entries.length - 3);
      expect(progress, <int>[500, 1000, 1010]);
    });

    test('a failing chunk throws after the earlier chunks were saved', () async {
      int calls = 0;
      h.api.rpcs['bulk_upsert_pharmacy_products'] = (Map<String, dynamic> p) {
        calls++;
        if (calls == 2) throw const AppFailure('network');
        return <String, dynamic>{'inserted': 500, 'updated': 0, 'skipped': 0};
      };
      final List<ListingEntry> entries = <ListingEntry>[
        for (int i = 0; i < ListingRepository.importChunk + 5; i++) ListingEntry(medicineId: 'm$i', price: 1000),
      ];
      await expectLater(repo.bulkUpsert('ph-1', entries), throwsA(isA<AppFailure>()));
      expect(calls, 2);
    });

    test('matchNames keeps the suggestions aligned with the names, best first, across chunks', () async {
      h.api.rpcs['match_medicine_names'] = (Map<String, dynamic> p) {
        final List<dynamic> names = p['p_names'] as List<dynamic>;
        return <Map<String, dynamic>>[
          // the first and the last name of the chunk each get two suggestions (worse one listed first on purpose)
          for (final int idx in <int>[1, names.length]) ...<Map<String, dynamic>>[
            <String, dynamic>{'idx': idx, 'medicine_id': 'low-$idx', 'name_en': 'Low $idx', 'score': 0.5},
            <String, dynamic>{'idx': idx, 'medicine_id': 'high-$idx', 'name_en': 'High $idx', 'score': 0.9},
          ],
        ];
      };
      final List<String> names = <String>[for (int i = 0; i < ListingRepository.matchChunk + 3; i++) 'name $i'];

      final List<List<NameMatch>> out = await repo.matchNames(names);

      expect(h.api.rpcCount('match_medicine_names'), 2);
      expect(out.length, names.length);
      expect(out[0].map((NameMatch m) => m.medicine.id), <String>['high-1', 'low-1']);
      expect(out[ListingRepository.matchChunk - 1].map((NameMatch m) => m.medicine.id), <String>['high-100', 'low-100']);
      expect(out[ListingRepository.matchChunk].map((NameMatch m) => m.medicine.id), <String>['high-1', 'low-1']);
      expect(out[ListingRepository.matchChunk + 2].map((NameMatch m) => m.medicine.id), <String>['high-3', 'low-3']);
      expect(out[1], isEmpty, reason: 'a name nothing matched has no suggestions');
    });
  });

  group('ProductsController', () {
    setUp(() => signInMember(h));

    test('changing the filter reloads the list with that filter', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('a'), listRow('b', available: false), listRow('c', confirmedAt: daysAgo(20))]);
      final ProductsController c = ProductsController()..onInit();
      await c.paged.reload();
      expect(c.paged.items.length, 3);

      c.setFilter(ProductFilter.unavailable);
      await c.paged.reload();
      expect(c.paged.items.map((PharmacyProduct p) => p.id), <String>['b']);

      c.setFilter(ProductFilter.stale);
      await c.paged.reload();
      expect(c.paged.items.map((PharmacyProduct p) => p.id), <String>['c']);

      c.setFilter(ProductFilter.available);
      await c.paged.reload();
      expect(c.paged.items.map((PharmacyProduct p) => p.id), <String>['a', 'c']);
    });

    test('searching reloads with the text; the same text again does nothing', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1', en: 'Panadol'), listRow('p2', en: 'Amoxil', ar: 'أموكسيل')]);
      final ProductsController c = ProductsController()..onInit();
      c.search('amox');
      await Future<void>.delayed(Duration.zero);
      await c.paged.reload();
      expect(c.paged.items.map((PharmacyProduct p) => p.id), <String>['p2']);
      final int reads = h.api.calls.where((String l) => l == 'select:pharmacy_products').length;
      c.search('  amox ');
      expect(h.api.calls.where((String l) => l == 'select:pharmacy_products').length, reads);
    });

    test('selecting the active category again clears it', () async {
      final ProductsController c = ProductsController()..onInit();
      c.setCategory('cat-1');
      expect(c.categoryId.value, 'cat-1');
      c.setCategory('cat-1');
      expect(c.categoryId.value, isNull);
    });

    test('confirming the list asks first and sends nothing when declined', () async {
      h.api.rpcs['confirm_listing'] = (Map<String, dynamic> p) => <String, dynamic>{'confirmed': 7};
      final ProductsController c = ProductsController(confirm: no)..onInit();
      expect(await c.confirmListing(), isNull);
      expect(h.api.rpcCount('confirm_listing'), 0);
    });

    test('confirming the list calls the server and reports how many rows were confirmed', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('a')]);
      h.api.rpcs['confirm_listing'] = (Map<String, dynamic> p) => <String, dynamic>{'confirmed': 7};
      final ProductsController c = ProductsController(confirm: yes)..onInit();
      expect(await c.confirmListing(), 7);
      expect(h.api.rpcLog.single.params['p_pharmacy_id'], 'ph-1');
    });

    test('a failed confirmation returns null and keeps the failure', () async {
      h.api.rpcs['confirm_listing'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final ProductsController c = ProductsController(confirm: yes)..onInit();
      expect(await c.confirmListing(), isNull);
      expect(c.failure.value?.code, 'network');
    });

    test('the quick switch marks a medicine unavailable and reloads the list', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('a')]);
      h.api.rpcs['update_pharmacy_product'] = (Map<String, dynamic> p) {
        h.api.tables['pharmacy_products']!.first['is_available'] = p['p_is_available'];
        return <String, dynamic>{};
      };
      final ProductsController c = ProductsController()..onInit();
      await c.paged.reload();

      expect(await c.setAvailable(c.paged.items.single, false), isTrue);

      expect(h.api.rpcLog.last.params, <String, dynamic>{'p_product_id': 'a', 'p_price': null, 'p_is_available': false});
      expect(c.paged.items.single.isAvailable, isFalse);
    });

    test('the quick switch does nothing when the state already matches', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('a')]);
      final ProductsController c = ProductsController()..onInit();
      await c.paged.reload();
      expect(await c.setAvailable(c.paged.items.single, true), isFalse);
      expect(h.api.rpcCount('update_pharmacy_product'), 0);
    });

    test('opening a screen reloads the list when it comes back', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('a')]);
      final List<String> opened = <String>[];
      final ProductsController c = ProductsController(open: (String route) async {
        opened.add(route);
        h.api.tables['pharmacy_products']!.add(listRow('b'));
        return null;
      })
        ..onInit();
      await c.paged.reload();

      await c.openImport();
      expect(opened, <String>[AppRoutes.productImport]);
      expect(c.paged.items.length, 2);

      await c.openAdd();
      await c.openProduct(c.paged.items.first);
      expect(opened, <String>[AppRoutes.productImport, AppRoutes.productAdd, AppRoutes.product('a')]);
    });
  });

  group('ProductsController as a cashier', () {
    setUp(() => signInMember(h, memberRole: 'cashier'));

    test('only owners and managers manage the list; a cashier does not', () async {
      expect(ProductsController().canManage, isFalse);
    });
  });

  group('ProductsController as a manager', () {
    setUp(() => signInMember(h, memberRole: 'manager'));

    test('a manager manages the list', () async {
      expect(ProductsController().canManage, isTrue);
    });
  });

  group('ProductAddController', () {
    setUp(() => signInMember(h));

    late List<String> replaced;

    ProductAddController make({Future<Object?> Function(String route)? open}) {
      replaced = <String>[];
      return ProductAddController(open: open, replace: replaced.add)..onInit();
    }

    const Medicine panadol = Medicine(id: 'med-1', nameAr: 'بنادول', nameEn: 'Panadol');

    test('search starts at two characters and lists the catalogue results', () async {
      h.api.rpcs['search_medicines'] = (Map<String, dynamic> p) => <Map<String, dynamic>>[
            <String, dynamic>{'id': 'med-1', 'name_ar': 'بنادول', 'name_en': 'Panadol', 'strength': '500mg', 'dosage_form': 'أقراص', 'pharmacy_count': 0},
          ];
      final ProductAddController c = make();
      await c.search('p');
      expect(h.api.rpcCount('search_medicines'), 0);
      expect(c.searched.value, isFalse);
      await c.search('pan');
      expect(h.api.rpcCount('search_medicines'), 1);
      expect(c.results.single.id, 'med-1');
      expect(c.searched.value, isTrue);
    });

    test('a failed search is kept as a failure, not as "no results"', () async {
      h.api.rpcs['search_medicines'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final ProductAddController c = make();
      await c.search('pan');
      expect(c.searchFailure.value?.code, 'network');
      expect(c.searched.value, isFalse);
    });

    testWidgets('saving sends only the price, then opens the new product', (WidgetTester tester) async {
      h.api.rpcs['add_pharmacy_product'] = (Map<String, dynamic> p) => <String, dynamic>{'id': 'prod-new'};
      final ProductAddController c = make();
      await mount(tester, c.form);
      c.choose(panadol);
      c.price.text = '5500';

      expect(await c.save(), 'prod-new');

      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_medicine_id': 'med-1', 'p_price': 5500});
      expect(replaced, <String>[AppRoutes.product('prod-new')]);
    });

    testWidgets('nothing is sent until a medicine is chosen', (WidgetTester tester) async {
      final ProductAddController c = make();
      await mount(tester, c.form);
      c.price.text = '5500';
      expect(await c.save(), isNull);
      expect(h.api.rpcCount('add_pharmacy_product'), 0);
    });

    testWidgets('a medicine the pharmacy already lists offers to open the existing product', (WidgetTester tester) async {
      h.api.rpcs['add_pharmacy_product'] = (Map<String, dynamic> p) =>
          throw const AppFailure('invalid_input', details: <String, dynamic>{'reason': 'already_exists', 'product_id': 'prod-9'});
      final ProductAddController c = make();
      await mount(tester, c.form);
      c.choose(panadol);
      c.price.text = '5500';

      expect(await c.save(), isNull);
      expect(c.existingProductId.value, 'prod-9');
      expect(replaced, isEmpty);

      await c.openExisting();
      expect(replaced, <String>[AppRoutes.product('prod-9')]);
    });

    test('choosing another medicine clears the "already listed" hint', () async {
      final ProductAddController c = make();
      c.existingProductId.value = 'prod-9';
      c.choose(panadol);
      expect(c.existingProductId.value, isNull);
    });

    test('a medicine that comes back from the proposal screen is chosen right away', () async {
      final ProductAddController c = make(open: (String route) async => route == AppRoutes.productPropose ? panadol : null);
      await c.proposeNew();
      expect(c.selected.value?.id, 'med-1');
    });

    test('closing the proposal screen without a result chooses nothing', () async {
      final ProductAddController c = make(open: (String route) async => null);
      await c.proposeNew();
      expect(c.selected.value, isNull);
    });
  });

  group('ProductEditController', () {
    setUp(() => signInMember(h));

    testWidgets('sends only what changed', (WidgetTester tester) async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1', price: 5000)]);
      h.api.rpcs['update_pharmacy_product'] = (Map<String, dynamic> p) => <String, dynamic>{};
      int closed = 0;
      final ProductEditController c = ProductEditController(productId: 'p1', close: () => closed++);
      await mount(tester, c.form);
      await c.refresh();
      expect(c.price.text, '5000');
      expect(c.available.value, isTrue);
      c.price.text = '6000';

      expect(await c.save(), isTrue);

      expect(h.api.rpcLog.last.params, <String, dynamic>{'p_product_id': 'p1', 'p_price': 6000, 'p_is_available': null});
      expect(closed, 1);
    });

    testWidgets('the availability switch is sent when it changed', (WidgetTester tester) async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1')]);
      h.api.rpcs['update_pharmacy_product'] = (Map<String, dynamic> p) => <String, dynamic>{};
      final ProductEditController c = ProductEditController(productId: 'p1', close: () {});
      await mount(tester, c.form);
      await c.refresh();
      c.available.value = false;

      expect(c.changes(), (price: null, available: false));
      expect(await c.save(), isTrue);

      expect(h.api.rpcLog.last.params, <String, dynamic>{'p_product_id': 'p1', 'p_price': null, 'p_is_available': false});
    });

    testWidgets('nothing changed still confirms the row ("still correct") and closes', (WidgetTester tester) async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1')]);
      h.api.rpcs['update_pharmacy_product'] = (Map<String, dynamic> p) => <String, dynamic>{};
      int closed = 0;
      final ProductEditController c = ProductEditController(productId: 'p1', close: () => closed++);
      await mount(tester, c.form);
      await c.refresh();
      expect(c.changes(), isNull);

      expect(await c.save(), isTrue);

      expect(h.api.rpcLog.last.params, <String, dynamic>{'p_product_id': 'p1', 'p_price': null, 'p_is_available': null});
      expect(closed, 1);
    });

    testWidgets('a refused save keeps the screen open', (WidgetTester tester) async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1')]);
      h.api.rpcs['update_pharmacy_product'] = (Map<String, dynamic> p) => throw const AppFailure('forbidden');
      int closed = 0;
      final ProductEditController c = ProductEditController(productId: 'p1', close: () => closed++);
      await mount(tester, c.form);
      await c.refresh();
      c.price.text = '7000';

      expect(await c.save(), isFalse);
      expect(closed, 0);
    });

    test('a missing product is a not_found failure', () async {
      seedOrdered(h, <Map<String, dynamic>>[]);
      final ProductEditController c = ProductEditController(productId: 'nope');
      await c.refresh();
      expect(c.failure.value?.code, 'not_found');
    });
  });

  group('ProductDetailsController', () {
    setUp(() => signInMember(h));

    test('loads the row with its price, availability and confirmation time', () async {
      final DateTime when = daysAgo(3);
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1', price: 4200, confirmedAt: when)]);
      final ProductDetailsController c = ProductDetailsController(productId: 'p1');
      await c.refresh();
      expect(c.product.value!.price, 4200);
      expect(c.product.value!.isAvailable, isTrue);
      expect(c.product.value!.confirmedAt!.difference(when).inSeconds.abs(), lessThan(2));
      expect(c.canManage, isTrue);
    });

    test('a missing product is a not_found failure', () async {
      seedOrdered(h, <Map<String, dynamic>>[]);
      final ProductDetailsController c = ProductDetailsController(productId: 'nope');
      await c.refresh();
      expect(c.failure.value?.code, 'not_found');
    });

    test('marking unavailable asks for confirmation and sends nothing when declined', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1')]);
      h.api.rpcs['update_pharmacy_product'] = (Map<String, dynamic> p) => <String, dynamic>{};
      final ProductDetailsController c = ProductDetailsController(productId: 'p1', confirm: no);
      await c.refresh();
      await c.setAvailable(false);
      expect(h.api.rpcCount('update_pharmacy_product'), 0);
      expect(c.product.value!.isAvailable, isTrue);
    });

    test('marking unavailable and available again send is_available; only "unavailable" asks', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1')]);
      h.api.rpcs['update_pharmacy_product'] = (Map<String, dynamic> p) {
        h.api.tables['pharmacy_products']!.first['is_available'] = p['p_is_available'];
        return <String, dynamic>{};
      };
      int asked = 0;
      final ProductDetailsController c = ProductDetailsController(
        productId: 'p1',
        confirm: ({required String title, required String message, String? confirmLabel, bool destructive = false}) async {
          asked++;
          return true;
        },
      );
      await c.refresh();

      await c.setAvailable(false);
      expect(h.api.rpcLog.last.params, <String, dynamic>{'p_product_id': 'p1', 'p_price': null, 'p_is_available': false});
      expect(c.product.value!.isAvailable, isFalse);
      expect(asked, 1);

      await c.setAvailable(true);
      expect(h.api.rpcLog.last.params, <String, dynamic>{'p_product_id': 'p1', 'p_price': null, 'p_is_available': true});
      expect(c.product.value!.isAvailable, isTrue);
      expect(asked, 1);
    });

    test('"still correct" re-stamps the confirmation without changing anything else', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1', confirmedAt: daysAgo(20))]);
      h.api.rpcs['update_pharmacy_product'] = (Map<String, dynamic> p) {
        h.api.tables['pharmacy_products']!.first['confirmed_at'] = DateTime.now().toUtc().toIso8601String();
        return <String, dynamic>{};
      };
      final ProductDetailsController c = ProductDetailsController(productId: 'p1');
      await c.refresh();
      expect(c.product.value!.isStale(), isTrue);

      await c.confirmStillCorrect();

      expect(h.api.rpcLog.last.params, <String, dynamic>{'p_product_id': 'p1', 'p_price': null, 'p_is_available': null});
      expect(c.product.value!.isStale(), isFalse);
    });

    test('the edit screen is opened and the row re-read afterwards', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1', price: 5000)]);
      final List<String> opened = <String>[];
      final ProductDetailsController c = ProductDetailsController(
        productId: 'p1',
        open: (String route) async {
          opened.add(route);
          h.api.tables['pharmacy_products']!.first['price'] = 6500;
          return true;
        },
      );
      await c.refresh();
      await c.openEdit();
      expect(opened, <String>[AppRoutes.productEditOf('p1')]);
      expect(c.product.value!.price, 6500);
    });
  });

  group('ProductDetailsController as a cashier', () {
    setUp(() => signInMember(h, memberRole: 'cashier'));

    test('a cashier gets the product but not the management controls', () async {
      seedOrdered(h, <Map<String, dynamic>>[listRow('p1')]);
      final ProductDetailsController c = ProductDetailsController(productId: 'p1');
      await c.refresh();
      expect(c.product.value?.id, 'p1');
      expect(c.canManage, isFalse);
    });
  });
}
