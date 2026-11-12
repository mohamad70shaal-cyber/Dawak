// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/availability.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/features/customer/controllers/cart_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import 'customer_fixtures.dart';

void main() {
  late AppHarness h;
  late CartController cart;
  const CartPharmacy shifa = CartPharmacy(id: 'ph-1', name: 'الشفاء', currency: 'SYP');
  const CartPharmacy noor = CartPharmacy(id: 'ph-2', name: 'النور', currency: 'SYP');

  setUp(() async {
    h = await AppHarness.create();
    cart = Get.put<CartController>(CartController());
  });
  tearDown(() => h.dispose());

  CartAddResult addOne(PublicProduct p, {CartPharmacy pharmacy = shifa}) => cart.add(pharmacy, CartLine.fromProduct(p));

  group('adding', () {
    test('a new product is added with quantity 1 and the pharmacy is remembered', () {
      expect(addOne(product('p1')), CartAddResult.added);
      expect(cart.lines.single.quantity, 1);
      expect(cart.pharmacy.value?.id, 'ph-1');
      expect(cart.itemCount, 1);
    });

    test('adding the same product again increases the quantity up to the largest allowed per medicine', () {
      final PublicProduct p = product('p1');
      expect(addOne(p), CartAddResult.added);
      for (int i = 2; i <= CartController.maxQtyPerLine; i++) {
        expect(addOne(p), CartAddResult.increased, reason: 'unit $i');
      }
      expect(cart.lines.single.quantity, CartController.maxQtyPerLine);
      expect(addOne(p), CartAddResult.maxReached);
      expect(cart.lines.single.quantity, CartController.maxQtyPerLine);
    });

    test('a cart holds at most maxLines different medicines; one more is refused, an existing line can still grow', () {
      for (int i = 1; i <= CartController.maxLines; i++) {
        expect(addOne(product('p$i', medicineId: 'med-$i')), CartAddResult.added, reason: 'line $i');
      }
      expect(addOne(product('extra', medicineId: 'med-x')), CartAddResult.cartFull);
      expect(cart.lines.length, CartController.maxLines);
      expect(addOne(product('p1', medicineId: 'med-1')), CartAddResult.increased);
    });

    test('adding again takes the newest price and confirmation time', () {
      addOne(product('p1', price: 5000));
      addOne(product('p1', price: 5500, freshness: 'old'));
      expect(cart.lines.single.unitPrice, 5500);
      expect(cart.lines.single.freshness, Freshness.old);
    });

    test('a product from another pharmacy asks for confirmation and leaves the cart untouched', () {
      addOne(product('p1'));
      expect(addOne(product('p9'), pharmacy: noor), CartAddResult.needsReplace);
      expect(cart.lines.map((CartLine l) => l.productId), <String>['p1']);
      expect(cart.pharmacy.value?.id, 'ph-1');
    });

    test('replaceWith empties the cart and starts a new one at the new pharmacy', () {
      addOne(product('p1'));
      final CartAddResult r = cart.replaceWith(noor, CartLine.fromProduct(product('p9')));
      expect(r, CartAddResult.added);
      expect(cart.lines.map((CartLine l) => l.productId), <String>['p9']);
      expect(cart.pharmacy.value?.id, 'ph-2');
    });
  });

  group('editing', () {
    test('setQuantity clamps to the largest allowed, below one removes the line and the last removal resets the pharmacy', () {
      addOne(product('p1'));
      cart.setQuantity('p1', 99);
      expect(cart.lines.single.quantity, CartController.maxQtyPerLine);
      cart.setQuantity('p1', 0);
      expect(cart.isEmpty, isTrue);
      expect(cart.pharmacy.value, isNull);
    });

    test('remove keeps the other lines', () {
      addOne(product('p1'));
      addOne(product('p2', medicineId: 'med-2'));
      cart.remove('p1');
      expect(cart.lines.map((CartLine l) => l.productId), <String>['p2']);
      expect(cart.pharmacy.value, isNotNull);
    });

    test('totals and the order lines carry the prices the customer saw', () {
      addOne(product('p1', price: 1250.5));
      cart.setQuantity('p1', 3);
      expect(cart.total, 3751.5);
      expect(cart.itemCount, 3);
      final inputs = cart.toInputs();
      expect(inputs.single.productId, 'p1');
      expect(inputs.single.quantity, 3);
      expect(inputs.single.expectedUnitPrice, 1250.5);
    });
  });

  group('revalidate', () {
    test('updates the price and freshness of a line and reports the change', () async {
      addOne(product('p1', price: 5000));
      cart.setQuantity('p1', 4);
      serveCatalogue(h.api, <Map<String, dynamic>>[catalogueRow('p1', 'med-1', price: 6000, freshness: 'old')]);
      final CartSyncResult? r = await cart.revalidate();
      expect(r?.priceChanged, 1);
      expect(r?.unavailable, 0);
      expect(cart.lines.single.unitPrice, 6000);
      expect(cart.lines.single.quantity, 4, reason: 'the quantity is the customer\'s choice; no stock limits it');
      expect(cart.lines.single.freshness, Freshness.old);
      expect(cart.lastSync.value?.hasChanges, isTrue);
      expect(cart.canCheckout, isTrue);
    });

    test('an unchanged cart reports no changes', () async {
      addOne(product('p1', price: 5000));
      serveCatalogue(h.api, <Map<String, dynamic>>[catalogueRow('p1', 'med-1', price: 5000)]);
      final CartSyncResult? r = await cart.revalidate();
      expect(r?.hasChanges, isFalse);
    });

    test('a line the pharmacy no longer lists as available is flagged, not silently removed, and blocks checkout', () async {
      addOne(product('p1'));
      addOne(product('p2', medicineId: 'med-2'));
      serveCatalogue(h.api, <Map<String, dynamic>>[catalogueRow('p2', 'med-2')]);
      final CartSyncResult? r = await cart.revalidate();
      expect(r?.unavailable, 1);
      expect(cart.lineFor('p1')?.unavailable, isTrue);
      expect(cart.lineFor('p2')?.unavailable, isFalse);
      expect(cart.hasUnavailable, isTrue);
      expect(cart.canCheckout, isFalse);
    });

    test('a flagged line is usable again once the pharmacy lists it again', () async {
      addOne(product('p1'));
      serveCatalogue(h.api, <Map<String, dynamic>>[]);
      await cart.revalidate();
      expect(cart.canCheckout, isFalse);
      serveCatalogue(h.api, <Map<String, dynamic>>[catalogueRow('p1', 'med-1')]);
      await cart.revalidate();
      expect(cart.lines.single.unavailable, isFalse);
      expect(cart.canCheckout, isTrue);
    });

    test('a network failure keeps the local cart, flags the sync and returns null', () async {
      addOne(product('p1', price: 5000));
      h.api.rpcs['get_public_pharmacy_products'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final CartSyncResult? r = await cart.revalidate();
      expect(r, isNull);
      expect(cart.syncFailed.value, isTrue);
      expect(cart.lines.single.unitPrice, 5000);
      expect(cart.revalidating.value, isFalse);
    });

    test('the catalogue is read page by page until every line is found', () async {
      for (int i = 1; i <= 3; i++) {
        addOne(product('p$i', medicineId: 'med-$i'));
      }
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
        for (int i = 1; i <= 60; i++) catalogueRow('x$i', 'mx$i'),
        catalogueRow('p1', 'med-1'),
        catalogueRow('p2', 'med-2'),
        catalogueRow('p3', 'med-3'),
      ];
      serveCatalogue(h.api, rows);
      final CartSyncResult? r = await cart.revalidate();
      expect(r?.hasChanges, isFalse);
      expect(h.api.rpcCount('get_public_pharmacy_products'), 2, reason: 'lines are on the second page of 50');
    });

    test('an empty cart does not call the server', () async {
      final CartSyncResult? r = await cart.revalidate();
      expect(r?.hasChanges, isFalse);
      expect(h.api.rpcCount('get_public_pharmacy_products'), 0);
    });
  });

  group('lifecycle', () {
    test('completeOrder remembers the order for the result screen and empties the cart', () {
      addOne(product('p1'));
      cart.completeOrder(order('ord-1'));
      expect(cart.isEmpty, isTrue);
      expect(cart.lastPlaced.value?.id, 'ord-1');
    });

    test('signing out clears the cart and the last order', () async {
      h.signInAs('c1');
      await h.session.restore();
      addOne(product('p1'));
      cart.lastPlaced.value = order('ord-1');
      await h.session.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(cart.isEmpty, isTrue);
      expect(cart.lastPlaced.value, isNull);
    });

    test('medicine info of a line follows the catalogue after revalidation', () async {
      addOne(product('p1'));
      serveCatalogue(h.api, <Map<String, dynamic>>[catalogueRow('p1', 'med-1', ar: 'بنادول فوار', en: 'Panadol Soluble')]);
      await cart.revalidate();
      final Medicine m = cart.lines.single.medicine;
      expect(m.nameAr, 'بنادول فوار');
    });
  });

  group('a pharmacy\'s live answer as a cart line', () {
    AvailabilityOffer offerOf(String? productId, {double price = 4200}) => AvailabilityOffer.fromJson(Fx.requestOfferRow('ph-1', price: price, productId: productId));

    test('carries the answered price, counts as freshly confirmed and starts with one unit', () {
      final CartLine? l = CartLine.fromAnswer(offerOf('pp-9'), const Medicine(id: 'med-1', nameAr: 'بنادول'));
      expect(l, isNotNull);
      expect(l!.productId, 'pp-9');
      expect(l.unitPrice, 4200);
      expect(l.quantity, 1);
      expect(l.freshness, Freshness.recent);
      expect(l.confirmedAt, isNotNull);
    });

    test('without a row in the pharmacy\'s list there is nothing to reserve', () {
      expect(CartLine.fromAnswer(offerOf(null), const Medicine(id: 'med-1')), isNull);
      expect(CartLine.fromAnswer(offerOf(''), const Medicine(id: 'med-1')), isNull);
    });

    test('goes into the cart like any other line', () {
      final CartLine line = CartLine.fromAnswer(offerOf('pp-9'), const Medicine(id: 'med-1'))!;
      expect(cart.add(shifa, line), CartAddResult.added);
      expect(cart.toInputs().single.expectedUnitPrice, 4200);
    });
  });
}
