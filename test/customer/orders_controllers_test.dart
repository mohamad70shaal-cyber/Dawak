// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/base/base_controller.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/features/customer/controllers/customer_orders_controller.dart';
import 'package:dawak/features/customer/controllers/order_details_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';

void main() {
  late AppHarness h;
  setUp(() async {
    h = await AppHarness.create();
    h.signInAs('c1');
    await h.session.restore();
  });
  tearDown(() => h.dispose());

  void seedOrders() {
    h.api.tables['orders'] = <Map<String, dynamic>>[
      Fx.orderRow('o1', 'c1', 'ph-1', status: 'pending')..['created_at'] = '2026-10-10T09:00:00Z',
      Fx.orderRow('o2', 'c1', 'ph-1', status: 'completed')..['created_at'] = '2026-10-09T09:00:00Z',
      Fx.orderRow('o3', 'c1', 'ph-1', status: 'ready_for_pickup')..['created_at'] = '2026-10-08T09:00:00Z',
      Fx.orderRow('o4', 'c1', 'ph-1', status: 'cancelled')..['created_at'] = '2026-10-07T09:00:00Z',
    ];
  }

  group('CustomerOrdersController', () {
    test('lists the orders newest first', () async {
      seedOrders();
      final CustomerOrdersController c = CustomerOrdersController()..onInit();
      await c.reload();
      expect(c.paged.items.map((o) => o.id), <String>['o1', 'o2', 'o3', 'o4']);
      expect(c.paged.status.value, ViewStatus.ready);
    });

    test('the active filter keeps only pending, accepted and ready orders', () async {
      seedOrders();
      final CustomerOrdersController c = CustomerOrdersController()..onInit();
      await c.setActiveOnly(true);
      expect(c.paged.items.map((o) => o.id), <String>['o1', 'o3']);
      await c.setActiveOnly(false);
      expect(c.paged.items.length, 4);
    });

    test('choosing the filter that is already selected does not reload', () async {
      seedOrders();
      final CustomerOrdersController c = CustomerOrdersController()..onInit();
      await c.reload();
      final int selects = h.api.calls.where((String l) => l == 'select:orders').length;
      await c.setActiveOnly(false);
      expect(h.api.calls.where((String l) => l == 'select:orders').length, selects);
    });

    test('no orders gives the empty state; a failure gives the error state', () async {
      final CustomerOrdersController c = CustomerOrdersController()..onInit();
      await c.reload();
      expect(c.paged.status.value, ViewStatus.empty);
      h.api.failNext('select:orders', const AppFailure('network'));
      await c.reload();
      expect(c.paged.status.value, ViewStatus.error);
      expect(c.paged.failure.value?.code, 'network');
    });

    test('refreshList keeps the visible orders when the refresh fails', () async {
      seedOrders();
      final CustomerOrdersController c = CustomerOrdersController()..onInit();
      await c.reload();
      h.api.failNext('select:orders', const AppFailure('network'));
      await c.refreshList();
      expect(c.paged.items.length, 4);
      expect(c.paged.status.value, ViewStatus.ready);
    });
  });

  group('OrderDetailsController', () {
    OrderDetailsController make(String id) => OrderDetailsController(id)..onInit();

    test('loads an order of the customer', () async {
      seedOrders();
      final OrderDetailsController c = make('o1');
      await c.reload();
      expect(c.status.value, ViewStatus.ready);
      expect(c.order.value?.publicRef, 'DWK-ABCDE12345');
      expect(c.order.value?.items.single.quantity, 2);
      expect(c.canCancel, isTrue);
    });

    test('an order that is not visible is not_found', () async {
      final OrderDetailsController c = make('nope');
      await c.reload();
      expect(c.status.value, ViewStatus.error);
      expect(c.failure.value?.code, 'not_found');
    });

    test('a completed order cannot be cancelled by the customer', () async {
      seedOrders();
      final OrderDetailsController c = make('o2');
      await c.reload();
      expect(c.canCancel, isFalse);
    });

    test('cancel sends the reason, shows the new state and refreshes the orders list', () async {
      seedOrders();
      h.api.rpcs['cancel_order'] = (Map<String, dynamic> p) => Fx.orderRow(p['p_order_id'] as String, 'c1', 'ph-1', status: 'cancelled');
      final CustomerOrdersController list = Get.put<CustomerOrdersController>(CustomerOrdersController());
      await list.reload();
      final OrderDetailsController c = make('o1');
      await c.reload();
      final bool ok = await c.cancel(reason: 'لم أعد بحاجة إليه');
      expect(ok, isTrue);
      expect(h.api.rpcLog.last.params['p_reason'], 'لم أعد بحاجة إليه');
      expect(c.order.value?.status, OrderStatus.cancelled);
      expect(h.api.calls.where((String l) => l == 'select:orders').length, greaterThanOrEqualTo(3), reason: 'list refreshed');
    });

    test('a refused cancel (the pharmacy acted first) re-reads the order so the screen shows the truth', () async {
      seedOrders();
      h.api.rpcs['cancel_order'] = (Map<String, dynamic> p) {
        h.api.tables['orders']!.firstWhere((Map<String, dynamic> r) => r['id'] == 'o1')['status'] = 'ready_for_pickup';
        throw const AppFailure('invalid_transition');
      };
      final OrderDetailsController c = make('o1');
      await c.reload();
      final bool ok = await c.cancel();
      expect(ok, isFalse);
      expect(c.failure.value?.code, 'invalid_transition');
      expect(c.order.value?.status, OrderStatus.readyForPickup);
      expect(c.status.value, ViewStatus.ready, reason: 'the page stays usable');
    });

    test('a second cancel while one is running is ignored', () async {
      seedOrders();
      h.api.delay = const Duration(milliseconds: 20);
      h.api.rpcs['cancel_order'] = (Map<String, dynamic> p) => Fx.orderRow('o1', 'c1', 'ph-1', status: 'cancelled');
      final OrderDetailsController c = make('o1');
      await c.reload();
      final Future<bool> a = c.cancel();
      final Future<bool> b = c.cancel();
      expect(await b, isFalse);
      expect(await a, isTrue);
      expect(h.api.rpcCount('cancel_order'), 1);
    });

    group('timeline', () {
      test('a pending order shows what is still to come', () async {
        seedOrders();
        final OrderDetailsController c = make('o1');
        await c.reload();
        expect(c.timeline.map((TrackStep s) => s.labelKey), <String>['c_track_placed', 'c_track_accepted', 'c_track_ready', 'c_track_completed']);
        expect(c.timeline.map((TrackStep s) => s.done), <bool>[true, false, false, false]);
        expect(c.timeline.first.current, isTrue);
      });

      test('an accepted order has the placed and accepted steps done', () async {
        h.api.tables['orders'] = <Map<String, dynamic>>[
          Fx.orderRow('o1', 'c1', 'ph-1', status: 'accepted')
            ..['accepted_at'] = '2026-10-10T10:00:00Z'
            ..['reservation_expires_at'] = DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(),
        ];
        final OrderDetailsController c = make('o1');
        await c.reload();
        expect(c.timeline.where((TrackStep s) => s.done).length, 2);
        expect(c.timeline.firstWhere((TrackStep s) => s.current).labelKey, 'c_track_accepted');
        expect(c.remaining, isNotNull);
        expect(c.remaining!.isNegative, isFalse);
      });

      test('a rejected order ends with a negative step and no future steps', () async {
        h.api.tables['orders'] = <Map<String, dynamic>>[
          Fx.orderRow('o1', 'c1', 'ph-1', status: 'rejected')..['rejected_at'] = '2026-10-10T09:30:00Z'..['reject_reason'] = 'غير متوفر',
        ];
        final OrderDetailsController c = make('o1');
        await c.reload();
        expect(c.timeline.map((TrackStep s) => s.labelKey), <String>['c_track_placed', 'c_track_rejected']);
        expect(c.timeline.last.negative, isTrue);
        expect(c.timeline.last.current, isTrue);
        expect(c.remaining, isNull, reason: 'nothing is kept for a rejected order');
      });

      test('steps are ordered by time', () async {
        h.api.tables['orders'] = <Map<String, dynamic>>[
          Fx.orderRow('o1', 'c1', 'ph-1', status: 'completed')
            ..['accepted_at'] = '2026-10-10T10:00:00Z'
            ..['ready_at'] = '2026-10-10T11:00:00Z'
            ..['completed_at'] = '2026-10-10T12:00:00Z',
        ];
        final OrderDetailsController c = make('o1');
        await c.reload();
        expect(c.timeline.map((TrackStep s) => s.labelKey), <String>['c_track_placed', 'c_track_accepted', 'c_track_ready', 'c_track_completed']);
        expect(c.timeline.every((TrackStep s) => s.done), isTrue);
      });
    });
  });
}
