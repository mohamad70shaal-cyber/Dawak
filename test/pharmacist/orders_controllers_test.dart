// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/data/models/order.dart';
import 'package:dawak/data/models/sale.dart';
import 'package:dawak/features/pharmacist/controllers/order_find_controller.dart';
import 'package:dawak/features/pharmacist/controllers/order_handover_controller.dart';
import 'package:dawak/features/pharmacist/controllers/pharmacist_order_details_controller.dart';
import 'package:dawak/features/pharmacist/controllers/pharmacist_orders_controller.dart';
import 'package:dawak/features/pharmacist/services/dialog_hooks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import 'pharmacist_fixtures.dart';

ConfirmFn answer(bool yes) =>
    ({required String title, required String message, String? confirmLabel, bool destructive = false}) async => yes;

ReasonFn reasonIs(String? reason) => ({
      required String title,
      required String label,
      String? message,
      String? confirmLabel,
      int minLength = 3,
      bool destructive = true,
    }) async =>
        reason;

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
    await signInMember(h);
  });
  tearDown(() => h.dispose());

  Map<String, dynamic> orderRow(String id, {String status = 'pending', String ref = 'DWK-ABCDE12345', String pharmacy = 'ph-1'}) =>
      Fx.orderRow(id, 'c1', pharmacy, status: status, ref: ref);

  void seedOrders(List<Map<String, dynamic>> rows) => h.api.tables['orders'] = rows;

  /// An RPC that moves the stored order to [to], like the database does, and returns the new row.
  void transition(String rpc, String to) {
    h.api.rpcs[rpc] = (Map<String, dynamic> p) {
      final Map<String, dynamic> row = h.api.tables['orders']!.firstWhere((Map<String, dynamic> r) => r['id'] == p['p_order_id']);
      row['status'] = to;
      return Map<String, dynamic>.from(row);
    };
  }

  Future<PharmacistOrderDetailsController> details(
    String status, {
    ConfirmFn? confirm,
    ReasonFn? ask,
    Future<Object?> Function(String route)? open,
    DateTime Function()? clock,
    Map<String, dynamic>? extra,
  }) async {
    final Map<String, dynamic> row = orderRow('o1', status: status)..addAll(extra ?? <String, dynamic>{});
    seedOrders(<Map<String, dynamic>>[row]);
    final PharmacistOrderDetailsController c =
        PharmacistOrderDetailsController(orderId: 'o1', confirm: confirm, askReason: ask, open: open, clock: clock);
    await c.refresh();
    return c;
  }

  group('what the buttons allow', () {
    test('each status offers exactly its own actions', () async {
      final Map<String, Set<String>> expected = <String, Set<String>>{
        'pending': <String>{'accept', 'reject'},
        'accepted': <String>{'ready', 'cancel'},
        'ready_for_pickup': <String>{'handover', 'cancel'},
        'expired': <String>{'reactivate'},
        'completed': <String>{},
        'rejected': <String>{},
        'cancelled': <String>{},
      };
      for (final MapEntry<String, Set<String>> e in expected.entries) {
        final PharmacistOrderDetailsController c = await details(e.key);
        final Set<String> got = <String>{
          if (c.canAccept) 'accept',
          if (c.canReject) 'reject',
          if (c.canMarkReady) 'ready',
          if (c.canCancel) 'cancel',
          if (c.canHandover) 'handover',
          if (c.canReactivate) 'reactivate',
        };
        expect(got, e.value, reason: e.key);
      }
    });
  });

  group('actions on one order', () {
    test('accepting asks first; declining sends nothing', () async {
      final PharmacistOrderDetailsController c = await details('pending', confirm: answer(false));
      transition('accept_order', 'accepted');
      expect(await c.accept(), isFalse);
      expect(h.api.rpcCount('accept_order'), 0);
    });

    test('accepting sends the order id and shows the new status', () async {
      final PharmacistOrderDetailsController c = await details('pending', confirm: answer(true));
      transition('accept_order', 'accepted');
      expect(await c.accept(), isTrue);
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_order_id': 'o1'});
      expect(c.order.value!.status, OrderStatus.accepted);
      expect(c.notice.value, isNull);
    });

    test('rejecting needs a reason; dismissing the dialog sends nothing', () async {
      transition('reject_order', 'rejected');
      final PharmacistOrderDetailsController dismissed = await details('pending', ask: reasonIs(null));
      expect(await dismissed.reject(), isFalse);
      expect(h.api.rpcCount('reject_order'), 0);

      final PharmacistOrderDetailsController c = await details('pending', ask: reasonIs('  الدواء غير متوفر  '));
      expect(await c.reject(), isTrue);
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_order_id': 'o1', 'p_reason': 'الدواء غير متوفر'});
      expect(c.order.value!.status, OrderStatus.rejected);
    });

    test('marking ready needs no dialog', () async {
      final PharmacistOrderDetailsController c = await details('accepted');
      transition('mark_order_ready', 'ready_for_pickup');
      expect(await c.markReady(), isTrue);
      expect(c.order.value!.status, OrderStatus.readyForPickup);
      expect(c.canHandover, isTrue);
    });

    test('cancelling an accepted reservation sends the reason', () async {
      final PharmacistOrderDetailsController c = await details('accepted', ask: reasonIs('الزبون لم يحضر'));
      transition('pharmacy_cancel_order', 'cancelled');
      expect(await c.cancel(), isTrue);
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_order_id': 'o1', 'p_reason': 'الزبون لم يحضر'});
      expect(c.order.value!.status, OrderStatus.cancelled);
    });

    test('an expired order can be reactivated after confirmation', () async {
      final PharmacistOrderDetailsController declined = await details('expired', confirm: answer(false));
      transition('reactivate_order', 'accepted');
      expect(await declined.reactivate(), isFalse);
      expect(h.api.rpcCount('reactivate_order'), 0);

      final PharmacistOrderDetailsController c = await details('expired', confirm: answer(true));
      expect(await c.reactivate(), isTrue);
      expect(c.order.value!.status, OrderStatus.accepted);
    });

    test('an action the status does not allow is never sent', () async {
      final PharmacistOrderDetailsController c = await details('completed', confirm: answer(true), ask: reasonIs('x'));
      expect(await c.accept(), isFalse);
      expect(await c.reject(), isFalse);
      expect(await c.markReady(), isFalse);
      expect(await c.cancel(), isFalse);
      expect(await c.reactivate(), isFalse);
      expect(h.api.rpcLog, isEmpty);
    });
  });

  group('refusals', () {
    test('invalid_transition: the order is re-read and the screen explains that it changed', () async {
      final PharmacistOrderDetailsController c = await details('pending', confirm: answer(true));
      h.api.rpcs['accept_order'] = (Map<String, dynamic> p) {
        h.api.tables['orders']!.first['status'] = 'cancelled'; // the customer cancelled meanwhile
        throw const AppFailure('invalid_transition');
      };
      expect(await c.accept(), isFalse);
      expect(c.notice.value, 'p_order_notice_changed'.tr);
      expect(c.order.value!.status, OrderStatus.cancelled);
      expect(c.canAccept, isFalse);
    });

    test('reservation_expired explains that the time is over', () async {
      final PharmacistOrderDetailsController c = await details('ready_for_pickup', ask: reasonIs('x'));
      h.api.rpcs['pharmacy_cancel_order'] = (Map<String, dynamic> p) => throw const AppFailure('reservation_expired');
      expect(await c.cancel(), isFalse);
      expect(c.notice.value, 'p_order_notice_expired'.tr);
    });

    test('any other failure shows its translated text', () async {
      final PharmacistOrderDetailsController c = await details('pending', confirm: answer(true));
      h.api.rpcs['accept_order'] = (Map<String, dynamic> p) => throw const AppFailure('forbidden');
      await c.accept();
      expect(c.notice.value, 'err_forbidden'.tr);
    });

    test('a successful action clears an earlier explanation', () async {
      final PharmacistOrderDetailsController c = await details('pending', confirm: answer(true));
      c.notice.value = 'old';
      transition('accept_order', 'accepted');
      await c.accept();
      expect(c.notice.value, isNull);
    });
  });

  group('reservation countdown', () {
    test('shows the time left and turns overdue once the clock passes the end', () async {
      DateTime clock = DateTime.utc(2026, 10, 10, 12);
      final PharmacistOrderDetailsController c = await details(
        'accepted',
        clock: () => clock,
        extra: <String, dynamic>{'reservation_expires_at': DateTime.utc(2026, 10, 10, 14).toIso8601String()},
      );
      expect(c.remaining, const Duration(hours: 2));
      expect(c.overdue, isFalse);

      clock = DateTime.utc(2026, 10, 10, 15);
      c.tick();
      expect(c.overdue, isTrue);
    });

    test('an order nobody has promised yet (pending) has no countdown', () async {
      final PharmacistOrderDetailsController c = await details('pending');
      expect(c.remaining, isNull);
      expect(c.overdue, isFalse);
    });
  });

  group('opening the handover', () {
    test('only a ready order opens the handover screen, then the order is re-read', () async {
      final List<String> routes = <String>[];
      final PharmacistOrderDetailsController c = await details('ready_for_pickup', open: (String r) async {
        routes.add(r);
        return null;
      });
      final int selectsBefore = h.api.calls.where((String l) => l == 'select:orders').length;
      await c.openHandover();
      expect(routes, <String>[AppRoutes.orderHandoverOf('o1')]);
      expect(h.api.calls.where((String l) => l == 'select:orders').length, selectsBefore + 1);
    });

    test('an accepted order does not', () async {
      final List<String> routes = <String>[];
      final PharmacistOrderDetailsController c = await details('accepted', open: (String r) async {
        routes.add(r);
        return null;
      });
      await c.openHandover();
      expect(routes, isEmpty);
    });
  });

  group('OrderHandoverController', () {
    Future<OrderHandoverController> handover(String status, List<String> replaced) async {
      seedOrders(<Map<String, dynamic>>[orderRow('o1', status: status, ref: 'DWK-ABCDE12345')]);
      final OrderHandoverController c = OrderHandoverController(orderId: 'o1', replace: replaced.add);
      await c.refresh();
      return c;
    }

    Future<void> mount(WidgetTester tester, GlobalKey<FormState> key) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: key, child: const SizedBox()))));

    test('the code is upper-cased and stripped of spaces', () async {
      final OrderHandoverController c = await handover('ready_for_pickup', <String>[]);
      expect(c.normalize('  dwk-abcde 12345 '), 'DWK-ABCDE12345');
      expect(c.referenceRule('   '), 'val_required'.tr);
      expect(c.referenceRule('dwk-1'), isNull);
    });

    test('only a ready order can be handed over', () async {
      for (final String s in <String>['pending', 'accepted', 'completed', 'expired']) {
        expect((await handover(s, <String>[])).canComplete, isFalse, reason: s);
      }
      expect((await handover('ready_for_pickup', <String>[])).canComplete, isTrue);
    });

    testWidgets('confirming sends the normalised code and opens the sale in place of the screen', (WidgetTester tester) async {
      final List<String> replaced = <String>[];
      h.api.rpcs['complete_order'] = (Map<String, dynamic> p) => Fx.saleJson('sale-7');
      final OrderHandoverController c = await handover('ready_for_pickup', replaced);
      await mount(tester, c.form);
      c.reference.text = ' dwk-abcde12345 ';

      final Sale? sale = await c.complete();

      expect(sale?.id, 'sale-7');
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_order_id': 'o1', 'p_reference': 'DWK-ABCDE12345'});
      expect(replaced, <String>[AppRoutes.sale('sale-7')]);
    });

    testWidgets('a wrong code is explained and the order is not re-read', (WidgetTester tester) async {
      final List<String> replaced = <String>[];
      h.api.rpcs['complete_order'] = (Map<String, dynamic> p) => throw const AppFailure('reference_mismatch');
      final OrderHandoverController c = await handover('ready_for_pickup', replaced);
      await mount(tester, c.form);
      c.reference.text = 'DWK-WRONG';
      final int selectsBefore = h.api.calls.where((String l) => l == 'select:orders').length;

      expect(await c.complete(), isNull);

      expect(c.notice.value, 'p_handover_mismatch'.tr);
      expect(replaced, isEmpty);
      expect(h.api.calls.where((String l) => l == 'select:orders').length, selectsBefore);
    });

    testWidgets('an expired reservation is explained and the order is re-read', (WidgetTester tester) async {
      h.api.rpcs['complete_order'] = (Map<String, dynamic> p) {
        h.api.tables['orders']!.first['status'] = 'expired';
        throw const AppFailure('reservation_expired');
      };
      final OrderHandoverController c = await handover('ready_for_pickup', <String>[]);
      await mount(tester, c.form);
      c.reference.text = 'DWK-ABCDE12345';

      expect(await c.complete(), isNull);

      expect(c.notice.value, 'p_order_notice_expired'.tr);
      expect(c.order.value!.status, OrderStatus.expired);
      expect(c.canComplete, isFalse);
    });

    testWidgets('an order that changed state meanwhile is explained', (WidgetTester tester) async {
      h.api.rpcs['complete_order'] = (Map<String, dynamic> p) {
        h.api.tables['orders']!.first['status'] = 'cancelled';
        throw const AppFailure('invalid_transition');
      };
      final OrderHandoverController c = await handover('ready_for_pickup', <String>[]);
      await mount(tester, c.form);
      c.reference.text = 'DWK-ABCDE12345';
      await c.complete();
      expect(c.notice.value, 'p_order_notice_changed'.tr);
      expect(c.order.value!.status, OrderStatus.cancelled);
    });

    testWidgets('nothing is sent while the order is not ready', (WidgetTester tester) async {
      h.api.rpcs['complete_order'] = (Map<String, dynamic> p) => Fx.saleJson('sale-1');
      final OrderHandoverController c = await handover('accepted', <String>[]);
      await mount(tester, c.form);
      c.reference.text = 'DWK-ABCDE12345';
      expect(await c.complete(), isNull);
      expect(h.api.rpcCount('complete_order'), 0);
    });
  });

  group('OrderFindController', () {
    Future<void> mount(WidgetTester tester, GlobalKey<FormState> key) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: key, child: const SizedBox()))));

    test('the code is normalised and its length checked', () {
      final OrderFindController c = OrderFindController();
      expect(OrderFindController.normalize(' dwk 12ab '), 'DWK12AB');
      expect(c.referenceRule(''), 'val_required'.tr);
      expect(c.referenceRule('abc'), isNotNull);
      expect(c.referenceRule('DWK-ABCDE12345'), isNull);
      expect(c.referenceRule('X' * 31), isNotNull);
    });

    testWidgets('a known code opens the order', (WidgetTester tester) async {
      final List<String> opened = <String>[];
      h.api.rpcs['find_order_by_ref'] = (Map<String, dynamic> p) => orderRow('o9');
      final OrderFindController c = OrderFindController(open: opened.add);
      await mount(tester, c.form);
      c.reference.text = ' dwk-abcde12345';

      final Order? o = await c.find();

      expect(o?.id, 'o9');
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_ref': 'DWK-ABCDE12345'});
      expect(opened, <String>[AppRoutes.pharmacistOrder('o9')]);
    });

    testWidgets('an unknown code says so and opens nothing', (WidgetTester tester) async {
      final List<String> opened = <String>[];
      h.api.rpcs['find_order_by_ref'] = (Map<String, dynamic> p) => throw const AppFailure('not_found');
      final OrderFindController c = OrderFindController(open: opened.add);
      await mount(tester, c.form);
      c.reference.text = 'DWK-NOSUCHCODE';

      expect(await c.find(), isNull);

      expect(c.notice.value, 'p_find_not_found'.tr);
      expect(opened, isEmpty);
    });

    testWidgets('another failure shows its own text', (WidgetTester tester) async {
      h.api.rpcs['find_order_by_ref'] = (Map<String, dynamic> p) => throw const AppFailure('rate_limited');
      final OrderFindController c = OrderFindController(open: (String _) {});
      await mount(tester, c.form);
      c.reference.text = 'DWK-ABCDE12345';
      await c.find();
      expect(c.notice.value, 'err_rate_limited'.tr);
    });
  });

  group('PharmacistOrdersController', () {
    setUp(() {
      h.api.rpcs['expire_reservations'] = (Map<String, dynamic> p) => <String, dynamic>{'expired': 0};
      seedOrders(<Map<String, dynamic>>[
        orderRow('new1'),
        orderRow('new2'),
        orderRow('acc1', status: 'accepted'),
        orderRow('rdy1', status: 'ready_for_pickup'),
        orderRow('done1', status: 'completed'),
        orderRow('rej1', status: 'rejected'),
        orderRow('can1', status: 'cancelled'),
        orderRow('exp1', status: 'expired'),
        orderRow('other', pharmacy: 'ph-other'),
      ]);
    });

    List<String> ids(PharmacistOrdersController c, OrderTab t) => c.pageFor(t).items.map((Order o) => o.id).toList()..sort();

    test('every tab lists its statuses for this pharmacy only', () async {
      final PharmacistOrdersController c = PharmacistOrdersController()..onInit();
      await c.refreshAll();
      expect(ids(c, OrderTab.fresh), <String>['new1', 'new2']);
      expect(ids(c, OrderTab.accepted), <String>['acc1']);
      expect(ids(c, OrderTab.ready), <String>['rdy1']);
      expect(ids(c, OrderTab.history), <String>['can1', 'done1', 'rej1']);
      expect(ids(c, OrderTab.expired), <String>['exp1']);
    });

    test('expired reservations are swept before the lists load', () async {
      final PharmacistOrdersController c = PharmacistOrdersController()..onInit();
      await c.refreshAll();
      final int sweep = h.api.calls.indexOf('rpc:expire_reservations');
      final int firstSelect = h.api.calls.indexOf('select:orders');
      expect(sweep, greaterThanOrEqualTo(0));
      expect(sweep, lessThan(firstSelect));
      expect(h.api.rpcLog.first.params, <String, dynamic>{'p_pharmacy_id': 'ph-1'});
    });

    test('a failing sweep does not stop the lists from loading', () async {
      h.api.rpcs['expire_reservations'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final PharmacistOrdersController c = PharmacistOrdersController()..onInit();
      await c.refreshAll();
      expect(ids(c, OrderTab.fresh), <String>['new1', 'new2']);
    });

    test('opening an order reloads the tabs when the user comes back', () async {
      final List<String> routes = <String>[];
      final PharmacistOrdersController c = PharmacistOrdersController(open: (String r) async {
        routes.add(r);
        return null;
      })
        ..onInit();
      await c.refreshAll();
      final Order o = c.pageFor(OrderTab.fresh).items.first;
      h.api.tables['orders']!.firstWhere((Map<String, dynamic> r) => r['id'] == o.id)['status'] = 'accepted';

      await c.openOrder(o);

      expect(routes, <String>[AppRoutes.pharmacistOrder(o.id)]);
      expect(ids(c, OrderTab.accepted), contains(o.id));
    });
  });
}
