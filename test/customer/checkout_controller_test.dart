// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/features/customer/controllers/cart_controller.dart';
import 'package:dawak/features/customer/controllers/checkout_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import 'customer_fixtures.dart';

void main() {
  late AppHarness h;
  late CartController cart;
  late int resultShown;
  const CartPharmacy shifa = CartPharmacy(id: 'ph-1', name: 'الشفاء', currency: 'SYP');

  setUp(() async {
    h = await AppHarness.create();
    h.signInAs('c1');
    await h.session.restore();
    cart = Get.put<CartController>(CartController());
    resultShown = 0;
    cart.add(shifa, CartLine.fromProduct(product('p1', price: 5000)));
    cart.setQuantity('p1', 2);
    serveCatalogue(h.api, <Map<String, dynamic>>[catalogueRow('p1', 'med-1', price: 5000)]);
  });
  tearDown(() => h.dispose());

  CheckoutController make() => CheckoutController(showResult: () => resultShown++)..onInit();

  /// The controller validates its form, so a (field-less) Form must be mounted for `form.currentState`.
  Future<CheckoutController> mounted(WidgetTester tester) async {
    final CheckoutController c = make();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: c.form, child: const SizedBox()))));
    return c;
  }

  void orderSucceeds() => h.api.rpcs['create_order'] = (Map<String, dynamic> p) => Fx.orderRow('ord-1', 'c1', 'ph-1', subtotal: 10000);

  group('happy path', () {
    testWidgets('sends the lines with the seen prices, then clears the cart and shows the result', (WidgetTester tester) async {
      orderSucceeds();
      final CheckoutController c = await mounted(tester);
      final bool ok = await c.submitOrder();
      expect(ok, isTrue);
      final Map<String, dynamic> p = h.api.rpcLog.single.params;
      expect(p['p_pharmacy_id'], 'ph-1');
      expect((p['p_items'] as List<dynamic>).single, <String, dynamic>{'product_id': 'p1', 'quantity': 2, 'expected_unit_price': 5000.0});
      expect(p['p_notes'], isNull, reason: 'empty notes are sent as null');
      expect(p['p_idempotency_key'], startsWith('ord-'));
      expect(cart.isEmpty, isTrue);
      expect(cart.lastPlaced.value?.id, 'ord-1');
      expect(resultShown, 1);
    });

    testWidgets('notes are trimmed and sent', (WidgetTester tester) async {
      orderSucceeds();
      final CheckoutController c = await mounted(tester);
      c.notes.text = '  العبوة الصغيرة  ';
      await c.submitOrder();
      expect(h.api.rpcLog.single.params['p_notes'], 'العبوة الصغيرة');
    });

    testWidgets('an empty cart never reaches the server', (WidgetTester tester) async {
      cart.clear();
      final CheckoutController c = await mounted(tester);
      expect(await c.submitOrder(), isFalse);
      expect(h.api.rpcCount('create_order'), 0);
    });
  });

  group('idempotency', () {
    testWidgets('a retry of the same payload after a network error reuses the key', (WidgetTester tester) async {
      final List<Object?> keys = <Object?>[];
      bool first = true;
      h.api.rpcs['create_order'] = (Map<String, dynamic> p) {
        keys.add(p['p_idempotency_key']);
        if (first) {
          first = false;
          throw const AppFailure('network');
        }
        return Fx.orderRow('ord-1', 'c1', 'ph-1');
      };
      final CheckoutController c = await mounted(tester);
      expect(await c.submitOrder(), isFalse);
      expect(cart.isEmpty, isFalse, reason: 'the cart is kept until the server confirmed');
      expect(c.failure.value?.code, 'network');
      expect(await c.submitOrder(), isTrue);
      expect(keys.length, 2);
      expect(keys[0], keys[1]);
    });

    testWidgets('a changed payload gets a new key', (WidgetTester tester) async {
      final List<Object?> keys = <Object?>[];
      h.api.rpcs['create_order'] = (Map<String, dynamic> p) {
        keys.add(p['p_idempotency_key']);
        throw const AppFailure('network');
      };
      final CheckoutController c = await mounted(tester);
      await c.submitOrder();
      c.notes.text = 'تغيّر الطلب';
      await c.submitOrder();
      expect(keys[0], isNot(keys[1]));
    });

    testWidgets('after success the next order starts with a fresh key', (WidgetTester tester) async {
      final List<Object?> keys = <Object?>[];
      h.api.rpcs['create_order'] = (Map<String, dynamic> p) {
        keys.add(p['p_idempotency_key']);
        return Fx.orderRow('ord-${keys.length}', 'c1', 'ph-1');
      };
      final CheckoutController c = await mounted(tester);
      await c.submitOrder();
      cart.add(shifa, CartLine.fromProduct(product('p1', price: 5000)));
      cart.setQuantity('p1', 2);
      await c.submitOrder();
      expect(keys[0], isNot(keys[1]));
    });
  });

  group('server rejections leave a consistent screen', () {
    testWidgets('price_changed refreshes the price, explains it and keeps the cart', (WidgetTester tester) async {
      h.api.rpcs['create_order'] = (Map<String, dynamic> p) => throw const AppFailure('price_changed');
      serveCatalogue(h.api, <Map<String, dynamic>>[catalogueRow('p1', 'med-1', price: 6000)]);
      final CheckoutController c = await mounted(tester);
      expect(await c.submitOrder(), isFalse);
      expect(cart.lines.single.unitPrice, 6000);
      expect(c.notice.value, 'c_notice_price_changed'.tr);
      expect(cart.isEmpty, isFalse);
      expect(resultShown, 0);
    });

    testWidgets('after a price change the confirmation uses the new price and a new key', (WidgetTester tester) async {
      final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
      h.api.rpcs['create_order'] = (Map<String, dynamic> p) {
        sent.add(p);
        if (sent.length == 1) throw const AppFailure('price_changed');
        return Fx.orderRow('ord-1', 'c1', 'ph-1');
      };
      serveCatalogue(h.api, <Map<String, dynamic>>[catalogueRow('p1', 'med-1', price: 6000)]);
      final CheckoutController c = await mounted(tester);
      await c.submitOrder();
      expect(await c.submitOrder(), isTrue);
      expect((sent[1]['p_items'] as List<dynamic>).single['expected_unit_price'], 6000.0);
      expect(sent[1]['p_idempotency_key'], isNot(sent[0]['p_idempotency_key']));
    });

    testWidgets('price_changed on a line the pharmacy no longer lists says it is unavailable instead', (WidgetTester tester) async {
      h.api.rpcs['create_order'] = (Map<String, dynamic> p) => throw const AppFailure('price_changed');
      serveCatalogue(h.api, <Map<String, dynamic>>[]);
      final CheckoutController c = await mounted(tester);
      await c.submitOrder();
      expect(c.notice.value, 'c_notice_unavailable'.tr);
      expect(cart.hasUnavailable, isTrue);
    });

    testWidgets('a code the app does not know is shown as the generic translated message, never as raw text', (WidgetTester tester) async {
      h.api.rpcs['create_order'] = (Map<String, dynamic> p) => throw const AppFailure('something_odd');
      final CheckoutController c = await mounted(tester);
      await c.submitOrder();
      expect(c.notice.value, 'err_unknown'.tr);
      expect(cart.isEmpty, isFalse);
    });

    testWidgets('product_unavailable flags the line and blocks the next attempt before the server', (WidgetTester tester) async {
      h.api.rpcs['create_order'] = (Map<String, dynamic> p) => throw const AppFailure('product_unavailable');
      serveCatalogue(h.api, <Map<String, dynamic>>[]);
      final CheckoutController c = await mounted(tester);
      await c.submitOrder();
      expect(c.notice.value, 'c_notice_unavailable'.tr);
      expect(cart.canCheckout, isFalse);
      final int before = h.api.rpcCount('create_order');
      expect(await c.submitOrder(), isFalse);
      expect(h.api.rpcCount('create_order'), before);
    });

    testWidgets('too_many_pending explains with the translated message', (WidgetTester tester) async {
      h.api.rpcs['create_order'] = (Map<String, dynamic> p) => throw const AppFailure('too_many_pending');
      final CheckoutController c = await mounted(tester);
      await c.submitOrder();
      expect(c.tooManyPending, isTrue);
      expect(c.notice.value, 'err_too_many_pending'.tr);
      expect(cart.isEmpty, isFalse);
    });

    testWidgets('pharmacy_not_active is flagged so the screen can offer to drop the cart', (WidgetTester tester) async {
      h.api.rpcs['create_order'] = (Map<String, dynamic> p) => throw const AppFailure('pharmacy_not_active');
      final CheckoutController c = await mounted(tester);
      await c.submitOrder();
      expect(c.pharmacyInactive, isTrue);
      expect(c.notice.value, 'err_pharmacy_not_active'.tr);
    });
  });

  group('guards', () {
    testWidgets('a second tap while the first is in flight does not send twice', (WidgetTester tester) async {
      orderSucceeds();
      h.api.delay = const Duration(milliseconds: 20);
      final CheckoutController c = await mounted(tester);
      final Future<bool> a = c.submitOrder();
      final Future<bool> b = c.submitOrder();
      expect(await b, isFalse);
      expect(await a, isTrue);
      expect(h.api.rpcCount('create_order'), 1);
    });

    testWidgets('an invalid form stops before the server', (WidgetTester tester) async {
      final CheckoutController c = make();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: c.form,
            child: TextFormField(controller: c.phone, validator: (String? v) => (v ?? '').isEmpty ? null : 'bad'),
          ),
        ),
      ));
      c.phone.text = 'abc';
      expect(await c.submitOrder(), isFalse);
      expect(h.api.rpcCount('create_order'), 0);
    });
  });

  group('refreshPrices', () {
    test('explains a price change found on opening the screen', () async {
      serveCatalogue(h.api, <Map<String, dynamic>>[catalogueRow('p1', 'med-1', price: 7000)]);
      final CheckoutController c = make();
      await c.refreshPrices();
      expect(c.notice.value, 'c_notice_price_changed'.tr);
      expect(cart.lines.single.unitPrice, 7000);
    });

    test('a failed refresh says so but keeps the cart usable', () async {
      h.api.rpcs['get_public_pharmacy_products'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final CheckoutController c = make();
      await c.refreshPrices();
      expect(c.notice.value, 'c_notice_sync_failed'.tr);
      expect(cart.lines.single.unitPrice, 5000);
    });

    test('nothing changed means no notice', () async {
      final CheckoutController c = make();
      await c.refreshPrices();
      expect(c.notice.value, isNull);
    });
  });
}
