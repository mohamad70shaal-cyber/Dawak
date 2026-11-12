// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/features/pharmacist/controllers/dashboard_controller.dart';
import 'package:dawak/features/pharmacist/controllers/products_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/harness.dart';
import 'pharmacist_fixtures.dart';

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
    await signInMember(h);
  });
  tearDown(() => h.dispose());

  Map<String, dynamic> dashJson({double total = 0}) => <String, dynamic>{
        'currency': 'SYP',
        'today': <String, dynamic>{'total': 100, 'count': 1},
        'week': <String, dynamic>{'total': 500, 'count': 5},
        'last_10_days': <String, dynamic>{'total': 900, 'count': 9},
        'month': <String, dynamic>{'total': 1500, 'count': 15},
        'range': <String, dynamic>{'from': '2026-10-10', 'to': '2026-10-19', 'total': total, 'count': 3},
        'daily_series': <Map<String, dynamic>>[
          <String, dynamic>{'day': '2026-10-18', 'total': 300, 'count': 2},
        ],
        'best_sellers': <Map<String, dynamic>>[
          <String, dynamic>{'product_id': 'p1', 'name': 'بنادول', 'quantity': 12, 'revenue': 60000},
        ],
        'listing': <String, dynamic>{'available': 40, 'unavailable': 6, 'stale': 4},
        'open_requests_count': 3,
        'pending_orders_count': 2,
        'recent_orders': <Map<String, dynamic>>[],
      };

  void serve() => h.api.rpcs['pharmacy_dashboard'] = (Map<String, dynamic> p) => dashJson();

  // 2026-10-19 is a Monday.
  DashboardController at(DateTime now) => DashboardController(clock: () => now);

  String day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  group('the days each chip stands for', () {
    test('today, last 10 days and month', () {
      final DashboardController c = at(DateTime(2026, 10, 19, 15, 30));
      c.range.value = DashRange.today;
      expect(c.currentRange, (from: DateTime(2026, 10, 19), to: DateTime(2026, 10, 19)));
      c.range.value = DashRange.last10;
      expect(c.currentRange, (from: DateTime(2026, 10, 10), to: DateTime(2026, 10, 19)));
      c.range.value = DashRange.month;
      expect(c.currentRange, (from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 19)));
    });

    test('the week starts on Saturday', () {
      final Map<DateTime, DateTime> expectedStart = <DateTime, DateTime>{
        DateTime(2026, 10, 17): DateTime(2026, 10, 17), // Saturday
        DateTime(2026, 10, 18): DateTime(2026, 10, 17), // Sunday
        DateTime(2026, 10, 19): DateTime(2026, 10, 17), // Monday
        DateTime(2026, 10, 22): DateTime(2026, 10, 17), // Thursday
        DateTime(2026, 10, 23): DateTime(2026, 10, 17), // Friday
        DateTime(2026, 10, 24): DateTime(2026, 10, 24), // next Saturday
      };
      for (final MapEntry<DateTime, DateTime> e in expectedStart.entries) {
        final DashboardController c = at(e.key.add(const Duration(hours: 10)));
        c.range.value = DashRange.week;
        expect(c.currentRange.from, e.value, reason: '${e.key}');
        expect(c.currentRange.to, e.key);
      }
    });

    test('a custom range without dates falls back to today', () {
      final DashboardController c = at(DateTime(2026, 10, 19));
      c.range.value = DashRange.custom;
      expect(c.currentRange, (from: DateTime(2026, 10, 19), to: DateTime(2026, 10, 19)));
    });
  });

  group('loading', () {
    test('asks the server for the default chip (last 10 days) as calendar dates', () async {
      serve();
      final DashboardController c = at(DateTime(2026, 10, 19, 9));
      await c.refresh();
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_from': '2026-10-10', 'p_to': '2026-10-19'});
      expect(c.data.value!.today.total, 100);
      expect(c.data.value!.bestSellers.single.quantity, 12);
      expect(c.data.value!.listing.available, 40);
      expect(c.data.value!.listing.unavailable, 6);
      expect(c.data.value!.listing.stale, 4);
      expect(c.data.value!.listing.total, 46);
      expect(c.data.value!.openRequestsCount, 3);
      expect(c.data.value!.pendingOrdersCount, 2);
      expect(c.currency, 'SYP');
    });

    test('choosing a chip reloads with its range; choosing the same chip again does not', () async {
      serve();
      final DashboardController c = at(DateTime(2026, 10, 19, 9));
      await c.refresh();
      c.select(DashRange.today);
      await Future<void>.delayed(Duration.zero);
      expect(h.api.rpcLog.last.params['p_from'], '2026-10-19');
      final int calls = h.api.rpcCount('pharmacy_dashboard');
      c.select(DashRange.today);
      await Future<void>.delayed(Duration.zero);
      expect(h.api.rpcCount('pharmacy_dashboard'), calls);
    });

    test('a slow answer for an old range never overwrites the newer one', () async {
      h.api.rpcs['pharmacy_dashboard'] = (Map<String, dynamic> p) => dashJson(total: p['p_from'] == '2026-10-19' ? 222 : 111);
      final DashboardController c = at(DateTime(2026, 10, 19, 9));
      h.api.delay = const Duration(milliseconds: 30);
      final Future<void> slow = c.refresh(); // last 10 days
      h.api.delay = Duration.zero;
      c.select(DashRange.today); // answers first
      await slow;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.data.value!.range.total, 222);
    });

    test('a failure on the first load is an error state; on a refresh the old figures stay', () async {
      h.api.rpcs['pharmacy_dashboard'] = (Map<String, dynamic> p) => throw StateError('boom');
      final DashboardController c = at(DateTime(2026, 10, 19, 9));
      await c.refresh();
      expect(c.failure.value, isNotNull);
      expect(c.data.value, isNull);

      serve();
      await c.refresh();
      expect(c.data.value, isNotNull);
      h.api.rpcs['pharmacy_dashboard'] = (Map<String, dynamic> p) => throw StateError('boom');
      await c.refresh(silent: true);
      expect(c.data.value, isNotNull, reason: 'the figures on screen are kept');
    });
  });

  group('the medicine list card', () {
    testWidgets('openStale sets the stale filter on the open list; openList leaves the filter alone', (WidgetTester tester) async {
      serve();
      await tester.pumpWidget(GetMaterialApp(home: const SizedBox())); // gives Get a navigator for the tab switch
      final DashboardController c = at(DateTime(2026, 10, 19, 9));
      final ProductsController products = Get.put<ProductsController>(ProductsController()..onInit());
      c.openStale();
      expect(products.filter.value, ProductFilter.stale);
      c.openList();
      expect(products.filter.value, ProductFilter.stale);
    });

    test('"my list is still correct" confirms the list and re-reads the figures', () async {
      serve();
      h.api.rpcs['confirm_listing'] = (Map<String, dynamic> p) => <String, dynamic>{'confirmed': 4};
      final ProductsController products = Get.put<ProductsController>(ProductsController(
        confirm: ({required String title, required String message, String? confirmLabel, bool destructive = false}) async => true,
      )..onInit());
      expect(products.canManage, isTrue);
      final DashboardController c = at(DateTime(2026, 10, 19, 9));
      await c.refresh();
      final int before = h.api.rpcCount('pharmacy_dashboard');

      await c.confirmList();

      expect(h.api.rpcCount('confirm_listing'), 1);
      expect(h.api.rpcCount('pharmacy_dashboard'), before + 1);
    });

    test('without the list tab open nothing happens', () async {
      serve();
      final DashboardController c = at(DateTime(2026, 10, 19, 9));
      await c.confirmList();
      expect(h.api.rpcCount('confirm_listing'), 0);
    });
  });

  group('custom range', () {
    test('reversed dates are refused and change nothing', () async {
      serve();
      final DashboardController c = at(DateTime(2026, 10, 19));
      expect(await c.setCustom(DateTime(2026, 10, 10), DateTime(2026, 10, 1)), isFalse);
      expect(c.range.value, DashRange.last10);
      expect(h.api.rpcCount('pharmacy_dashboard'), 0);
    });

    test('a span of more than one year is refused; exactly 365 days apart is the limit', () async {
      serve();
      final DashboardController c = at(DateTime(2026, 10, 19));
      expect(await c.setCustom(DateTime(2025, 10, 1), DateTime(2026, 10, 2)), isFalse); // 366 days apart
      expect(await c.setCustom(DateTime(2025, 10, 1), DateTime(2026, 10, 1)), isTrue); // 365 days apart
      expect(c.range.value, DashRange.custom);
    });

    test('a valid range is applied, sent as dates, and times of day are ignored', () async {
      serve();
      final DashboardController c = at(DateTime(2026, 10, 19));
      expect(await c.setCustom(DateTime(2026, 9, 1, 23, 59), DateTime(2026, 9, 30, 0, 1)), isTrue);
      expect(h.api.rpcLog.last.params['p_from'], day(DateTime(2026, 9, 1)));
      expect(h.api.rpcLog.last.params['p_to'], day(DateTime(2026, 9, 30)));
      expect(c.customFrom, DateTime(2026, 9, 1));
      expect(c.customTo, DateTime(2026, 9, 30));
    });

    test('selecting the custom chip without dates does nothing', () async {
      serve();
      final DashboardController c = at(DateTime(2026, 10, 19));
      c.select(DashRange.custom);
      expect(c.range.value, DashRange.last10);
    });
  });
}
