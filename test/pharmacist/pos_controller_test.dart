// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/data/models/sale.dart';
import 'package:dawak/features/pharmacist/controllers/pos_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import 'pharmacist_fixtures.dart';

void main() {
  late AppHarness h;
  late List<Sale> completed;

  setUp(() async {
    h = await AppHarness.create();
    completed = <Sale>[];
  });
  tearDown(() => h.dispose());

  PosController make() => PosController(showCompleted: completed.add)..onInit();

  Future<PosController> asOwner() async {
    await signInMember(h);
    return make();
  }

  Future<PosController> asCashier() async {
    await signInMember(h, memberRole: 'cashier');
    return make();
  }

  group('adding to the basket', () {
    test('adds a line, then increments it: the shelf decides, the app does not count stock', () async {
      final PosController c = await asOwner();
      final PharmacyProduct p = listItem('p1');
      expect(c.add(p), PosAdd.added);
      expect(c.add(p), PosAdd.added);
      expect(c.add(p), PosAdd.added);
      expect(c.qtyOf('p1'), 3);
      expect(c.lines.length, 1);
    });

    test('a medicine marked unavailable can still be sold: what is on the shelf is the truth', () async {
      final PosController c = await asOwner();
      expect(c.add(listItem('p1', available: false)), PosAdd.added);
      expect(c.lines.single.productId, 'p1');
    });

    test('the basket holds at most ${PosController.maxLines} different lines', () async {
      final PosController c = await asOwner();
      for (int i = 0; i < PosController.maxLines; i++) {
        expect(c.add(listItem('p$i')), PosAdd.added);
      }
      expect(c.add(listItem('extra')), PosAdd.basketFull);
      // an existing line can still grow
      expect(c.add(listItem('p0')), PosAdd.added);
      expect(c.lines.length, PosController.maxLines);
    });

    test('a single line stops at ${PosController.maxQtyPerLine}', () async {
      final PosController c = await asOwner();
      final PharmacyProduct p = listItem('p1');
      for (int i = 0; i < PosController.maxQtyPerLine; i++) {
        c.add(p);
      }
      expect(c.qtyOf('p1'), PosController.maxQtyPerLine);
      expect(c.add(p), PosAdd.atLimit);
    });

    test('setQuantity sets the quantity (at most the per-line cap) and a quantity below one removes the line', () async {
      final PosController c = await asOwner();
      c.add(listItem('p1'));
      c.setQuantity('p1', 50);
      expect(c.qtyOf('p1'), 50);
      c.setQuantity('p1', PosController.maxQtyPerLine + 500);
      expect(c.qtyOf('p1'), PosController.maxQtyPerLine);
      c.setQuantity('p1', 2);
      expect(c.qtyOf('p1'), 2);
      c.setQuantity('p1', 0);
      expect(c.isEmpty, isTrue);
    });
  });

  group('totals', () {
    test('subtotal, item count and total after a discount', () async {
      final PosController c = await asOwner();
      c.add(listItem('p1', price: 2500.5));
      c.setQuantity('p1', 3);
      c.add(listItem('p2', price: 1000));
      expect(c.itemCount, 4);
      expect(c.subtotal, 8501.5);
      expect(c.applyDiscount('501.5'), isTrue);
      expect(c.total, 8000);
    });

    test('removing lines lowers a discount that no longer fits the subtotal', () async {
      final PosController c = await asOwner();
      c.add(listItem('p1', price: 1000));
      c.add(listItem('p2', price: 4000));
      c.applyDiscount('4500');
      c.remove('p2');
      expect(c.discount.value, 1000);
      expect(c.total, 0);
      expect(c.notice.value, 'p_pos_discount_adjusted'.tr);
    });
  });

  group('discount rules', () {
    test('a cashier cannot give a discount', () async {
      final PosController c = await asCashier();
      c.add(listItem('p1', price: 1000));
      expect(c.canDiscount, isFalse);
      expect(c.applyDiscount('100'), isFalse);
      expect(c.discount.value, 0);
    });

    test('an empty text removes the discount', () async {
      final PosController c = await asOwner();
      c.add(listItem('p1', price: 1000));
      c.applyDiscount('100');
      expect(c.discount.value, 100);
      expect(c.applyDiscount(''), isTrue);
      expect(c.discount.value, 0);
    });

    test('a discount above the subtotal is refused and leaves no discount applied', () async {
      final PosController c = await asOwner();
      c.add(listItem('p1', price: 1000));
      c.applyDiscount('100');
      expect(c.applyDiscount('1500'), isFalse);
      expect(c.discount.value, 0);
      expect(c.discountError.value, 'p_pos_discount_too_high'.tr);
    });

    test('text that is not a number is refused and leaves no discount applied', () async {
      final PosController c = await asOwner();
      c.add(listItem('p1', price: 1000));
      c.applyDiscount('100');
      expect(c.applyDiscount('abc'), isFalse);
      expect(c.discount.value, 0);
      expect(c.discountError.value, isNotNull);
    });
  });

  group('checkout', () {
    void saleSucceeds() => h.api.rpcs['create_pos_sale'] = (Map<String, dynamic> p) => Fx.saleJson('sale-1', total: 9000);

    test('sends the lines with the price the cashier saw, empties the basket and shows the sale', () async {
      final PosController c = await asOwner();
      saleSucceeds();
      c.add(listItem('p1', price: 5000));
      c.setQuantity('p1', 2);
      c.add(listItem('p2', price: 1000));
      c.applyDiscount('2000');

      expect(await c.checkout(), isTrue);

      final Map<String, dynamic> p = h.api.rpcLog.single.params;
      expect(p['p_pharmacy_id'], 'ph-1');
      expect(p['p_discount'], 2000);
      expect(p['p_idempotency_key'], startsWith('pos-'));
      expect(p['p_items'], <Map<String, dynamic>>[
        <String, dynamic>{'product_id': 'p1', 'quantity': 2, 'expected_unit_price': 5000.0},
        <String, dynamic>{'product_id': 'p2', 'quantity': 1, 'expected_unit_price': 1000.0},
      ]);
      expect(c.isEmpty, isTrue);
      expect(c.discount.value, 0);
      expect(completed.single.id, 'sale-1');
    });

    test('an empty basket never reaches the server', () async {
      final PosController c = await asOwner();
      saleSucceeds();
      expect(await c.checkout(), isFalse);
      expect(h.api.rpcCount('create_pos_sale'), 0);
    });

    test('a second tap while the first is in flight is ignored', () async {
      final PosController c = await asOwner();
      saleSucceeds();
      h.api.delay = const Duration(milliseconds: 20);
      c.add(listItem('p1'));
      final Future<bool> first = c.checkout();
      final Future<bool> second = c.checkout();
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(h.api.rpcCount('create_pos_sale'), 1);
    });

    test('a retry of the same basket after a network error reuses the key; a changed basket gets a new one', () async {
      final PosController c = await asOwner();
      final List<Object?> keys = <Object?>[];
      int attempt = 0;
      h.api.rpcs['create_pos_sale'] = (Map<String, dynamic> p) {
        keys.add(p['p_idempotency_key']);
        attempt++;
        if (attempt <= 2) throw const AppFailure('network');
        return Fx.saleJson('sale-1');
      };
      c.add(listItem('p1'));

      expect(await c.checkout(), isFalse);
      expect(c.isEmpty, isFalse, reason: 'the basket is kept when the sale was not confirmed');
      expect(await c.checkout(), isFalse);
      expect(keys[1], keys[0]);

      c.add(listItem('p1')); // quantity 2: a different request
      expect(await c.checkout(), isTrue);
      expect(keys[2], isNot(keys[0]));
    });

    test('after a confirmed sale the next sale uses a fresh key', () async {
      final PosController c = await asOwner();
      final List<Object?> keys = <Object?>[];
      h.api.rpcs['create_pos_sale'] = (Map<String, dynamic> p) {
        keys.add(p['p_idempotency_key']);
        return Fx.saleJson('sale-${keys.length}');
      };
      c.add(listItem('p1'));
      await c.checkout();
      c.add(listItem('p1'));
      await c.checkout();
      expect(keys.toSet().length, 2);
    });
  });

  group('server refusals', () {
    test('product_unavailable drops the product that is no longer in the pharmacy list', () async {
      final PosController c = await asOwner();
      seedList(h, <Map<String, dynamic>>[listRow('p2')]); // p1 was removed from the list meanwhile
      h.api.rpcs['create_pos_sale'] = (Map<String, dynamic> p) => throw const AppFailure('product_unavailable');
      c.add(listItem('p1'));
      c.add(listItem('p2'));

      expect(await c.checkout(), isFalse);

      expect(c.lines.map((PosLine l) => l.productId), <String>['p2']);
      expect(c.notice.value, 'p_pos_notice_changed'.tr);
    });

    test('product_unavailable with nothing to fix shows the translated server message', () async {
      final PosController c = await asOwner();
      seedList(h, <Map<String, dynamic>>[listRow('p1')]);
      h.api.rpcs['create_pos_sale'] = (Map<String, dynamic> p) => throw const AppFailure('product_unavailable');
      c.add(listItem('p1'));

      expect(await c.checkout(), isFalse);

      expect(c.notice.value, 'err_product_unavailable'.tr);
      expect(c.isEmpty, isFalse);
    });

    test('price_changed takes the new price and leaves the sale for the cashier to confirm again', () async {
      final PosController c = await asOwner();
      seedList(h, <Map<String, dynamic>>[listRow('p1', price: 6000)]);
      h.api.rpcs['create_pos_sale'] = (Map<String, dynamic> p) => throw const AppFailure('price_changed');
      c.add(listItem('p1', price: 5000));

      expect(await c.checkout(), isFalse);

      expect(c.lines.single.unitPrice, 6000);
      expect(c.notice.value, 'p_pos_notice_changed'.tr);
      expect(h.api.rpcCount('create_pos_sale'), 1, reason: 'nothing is resent automatically');
    });

    test('forbidden while a discount is applied drops the discount', () async {
      final PosController c = await asOwner();
      h.api.rpcs['create_pos_sale'] = (Map<String, dynamic> p) => throw const AppFailure('forbidden');
      c.add(listItem('p1', price: 1000));
      c.applyDiscount('100');

      expect(await c.checkout(), isFalse);

      expect(c.discount.value, 0);
      expect(c.notice.value, 'p_pos_notice_no_discount'.tr);
    });

    test('any other failure shows its translated message and keeps the basket', () async {
      final PosController c = await asOwner();
      h.api.rpcs['create_pos_sale'] = (Map<String, dynamic> p) => throw const AppFailure('rate_limited');
      c.add(listItem('p1'));

      expect(await c.checkout(), isFalse);

      expect(c.notice.value, 'err_rate_limited'.tr);
      expect(c.isEmpty, isFalse);
    });
  });

  group('revalidate', () {
    test('reports what changed: removed and repriced lines; a product marked unavailable stays', () async {
      final PosController c = await asOwner();
      seedList(h, <Map<String, dynamic>>[
        listRow('unavailable', available: false), // still on the shelf: still sellable
        listRow('dearer', price: 7000),
        listRow('same'),
      ]);
      for (final String id in <String>['gone', 'unavailable', 'dearer', 'same']) {
        c.add(listItem(id, price: 5000));
      }
      c.setQuantity('dearer', 3);

      final PosSyncResult? r = await c.revalidate();

      expect(r!.removed, 1);
      expect(r.repriced, 1);
      expect(r.changed, isTrue);
      expect(c.lines.map((PosLine l) => l.productId), <String>['unavailable', 'dearer', 'same']);
      expect(c.qtyOf('dearer'), 3, reason: 'quantities are never touched');
      expect(c.lines.firstWhere((PosLine l) => l.productId == 'dearer').unitPrice, 7000);
      expect(c.notice.value, 'p_pos_notice_changed'.tr);
    });

    test('a product that no longer exists is removed', () async {
      final PosController c = await asOwner();
      seedList(h, <Map<String, dynamic>>[]);
      c.add(listItem('p1'));
      final PosSyncResult? r = await c.revalidate();
      expect(r!.removed, 1);
      expect(c.isEmpty, isTrue);
    });

    test('when the server cannot be reached the basket is left as it is', () async {
      final PosController c = await asOwner();
      c.add(listItem('p1'));
      h.api.failNext('select:pharmacy_products', const AppFailure('network'));
      expect(await c.revalidate(), isNull);
      expect(c.qtyOf('p1'), 1);
    });

    test('nothing changed leaves no notice', () async {
      final PosController c = await asOwner();
      seedList(h, <Map<String, dynamic>>[listRow('p1')]);
      c.add(listItem('p1'));
      final PosSyncResult? r = await c.revalidate();
      expect(r!.changed, isFalse);
      expect(c.notice.value, isNull);
    });
  });

  group('search', () {
    test('lists the whole pharmacy list (available or not) and filters by name', () async {
      final PosController c = await asOwner();
      seedList(h, <Map<String, dynamic>>[
        listRow('p1', ar: 'بنادول', en: 'Panadol'),
        listRow('p2', ar: 'أموكسيل', en: 'Amoxil'),
        listRow('p3', ar: 'بروفين', en: 'Brufen', available: false),
      ]);
      await c.products.reload();
      expect(c.products.items.map((PharmacyProduct p) => p.id).toSet(), <String>{'p1', 'p2', 'p3'});

      c.search('amox');
      await Future<void>.delayed(Duration.zero);
      await c.products.reload();
      expect(c.products.items.map((PharmacyProduct p) => p.id), <String>['p2']);
    });
  });
}
