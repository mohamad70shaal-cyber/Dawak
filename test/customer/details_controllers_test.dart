// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/base/base_controller.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/core/services/location_service.dart';
import 'package:dawak/data/models/geo.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/features/customer/controllers/cart_controller.dart';
import 'package:dawak/features/customer/controllers/customer_location.dart';
import 'package:dawak/features/customer/controllers/medicine_details_controller.dart';
import 'package:dawak/features/customer/controllers/pharmacy_details_controller.dart';
import 'package:dawak/features/customer/services/customer_dialog_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';
import 'customer_fixtures.dart';

/// A GPS that answers only after [wait] (the first fix of a cold phone).
class SlowGps extends FakeLocationGateway {
  SlowGps(this.wait);

  final Duration wait;

  @override
  Future<GeoPoint> currentPosition() async {
    await Future<void>.delayed(wait);
    return super.currentPosition();
  }
}

Future<bool> yes({required String title, required String message, String? confirmLabel, bool destructive = false}) async => true;

void main() {
  late AppHarness h;
  late CartController cart;
  late List<String> opened;
  setUp(() async {
    h = await AppHarness.create();
    cart = Get.put<CartController>(CartController());
    opened = <String>[];
    AskNearbyIntro.seen = false;
  });
  tearDown(() => h.dispose());

  /// Every `get_medicine_pharmacies` call is recorded; rows are served page by page like the real function.
  List<Map<String, dynamic>> serveOffers(List<Map<String, dynamic>> rows) {
    final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];
    h.api.rpcs['get_medicine_pharmacies'] = (Map<String, dynamic> p) {
      calls.add(p);
      return paged(rows)(p);
    };
    return calls;
  }

  MedicineDetailsController make({
    CustomerConfirmFn? confirm,
    CustomerLocation? where,
    Duration grace = const Duration(milliseconds: 40),
  }) =>
      MedicineDetailsController(
        'm1',
        cart: cart,
        confirm: confirm ?? yes,
        location: where,
        open: opened.add,
        locateGrace: grace,
      )..onInit();

  CustomerLocation noCache() => CustomerLocation(service: LocationService(h.gps, freshFor: Duration.zero));

  group('the medicine', () {
    test('loads', () async {
      h.api.tables['medicines'] = <Map<String, dynamic>>[Fx.medicineRow('m1')];
      final MedicineDetailsController c = make();
      await c.reload();
      expect(c.status.value, ViewStatus.ready);
      expect(c.medicine.value?.nameAr, 'بنادول');
    });

    test('an unknown medicine is a not_found failure, not a crash', () async {
      final MedicineDetailsController c = make();
      await c.reload();
      expect(c.status.value, ViewStatus.error);
      expect(c.failure.value?.code, 'not_found');
    });
  });

  group('the pharmacies that have it', () {
    test('with a position the request carries it and the list is marked as sorted by distance', () async {
      final List<Map<String, dynamic>> calls = serveOffers(<Map<String, dynamic>>[
        Fx.offerRow('ph-1', 'pp-1', name: 'الشفاء', distanceKm: 0.3),
        Fx.offerRow('ph-2', 'pp-2', name: 'النور', distanceKm: 1.2),
      ]);
      h.gps.position = const GeoPoint(33.5102, 36.2765);
      final MedicineDetailsController c = make();
      await c.ensureOffers();
      expect(calls.single['p_latitude'], 33.5102);
      expect(calls.single['p_longitude'], 36.2765);
      expect(c.located, isTrue);
      expect(c.offers.items.map((MedicineOffer o) => o.pharmacy.name), <String>['الشفاء', 'النور']);
      expect(c.offers.items.first.distanceKm, 0.3);
      expect(c.where.error.value, isNull);
    });

    test('offers load on the first request only, unless forced', () async {
      final List<Map<String, dynamic>> calls = serveOffers(<Map<String, dynamic>>[Fx.offerRow('ph-1', 'pp-1')]);
      final MedicineDetailsController c = make();
      await c.ensureOffers();
      await c.ensureOffers();
      expect(calls.length, 1);
      await c.ensureOffers(force: true);
      expect(calls.length, 2);
    });

    test('when the GPS fails the list still loads, without a position, and the failure is explained', () async {
      final List<Map<String, dynamic>> calls = serveOffers(<Map<String, dynamic>>[Fx.offerRow('ph-1', 'pp-1')]);
      h.gps.failure = const AppFailure('location_denied');
      final MedicineDetailsController c = make();
      await c.ensureOffers();
      expect(calls.single['p_latitude'], isNull);
      expect(c.located, isFalse);
      expect(c.offers.items.length, 1);
      expect(c.where.error.value, 'err_location_denied'.tr);
      expect(c.where.needsSettings.value, isFalse);
    });

    test('a slow first GPS fix does not hold the list back: it appears first and is re-read by distance when the fix arrives', () async {
      final List<Map<String, dynamic>> calls = serveOffers(<Map<String, dynamic>>[Fx.offerRow('ph-1', 'pp-1', distanceKm: 0.5)]);
      final CustomerLocation slow = CustomerLocation(service: LocationService(SlowGps(const Duration(milliseconds: 120))));
      final MedicineDetailsController c = make(where: slow, grace: const Duration(milliseconds: 10));
      await c.ensureOffers();
      expect(calls.length, 2);
      expect(calls[0]['p_latitude'], isNull, reason: 'the first read did not wait for the GPS');
      expect(calls[1]['p_latitude'], isNotNull);
      expect(c.located, isTrue);
    });

    test('later pages keep the position of the first page, so the order cannot change between pages', () async {
      final List<Map<String, dynamic>> calls = serveOffers(<Map<String, dynamic>>[
        for (int i = 1; i <= 25; i++) Fx.offerRow('ph-$i', 'pp-$i', name: 'ص$i', distanceKm: i / 10),
      ]);
      final MedicineDetailsController c = make(where: noCache());
      await c.ensureOffers();
      expect(c.offers.items.length, 20);
      // The customer walks on; the next page must still be measured from where the list started.
      h.gps.position = const GeoPoint(33.9, 36.9);
      await c.where.locate();
      await c.offers.loadMore();
      expect(c.offers.items.length, 25);
      expect(calls.last['p_latitude'], 33.5102, reason: 'the default position of the harness, i.e. the first page\'s');
    });

    test('"use my location" reads the GPS again and re-reads the list from the new position', () async {
      final List<Map<String, dynamic>> calls = serveOffers(<Map<String, dynamic>>[Fx.offerRow('ph-1', 'pp-1')]);
      h.gps.failure = const AppFailure('location_timeout');
      final MedicineDetailsController c = make(where: noCache());
      await c.ensureOffers();
      expect(c.located, isFalse);
      h.gps.failure = null;
      h.gps.position = const GeoPoint(33.6, 36.4);
      await c.useMyLocation();
      expect(c.located, isTrue);
      expect(calls.last['p_latitude'], 33.6);
      expect(c.where.error.value, isNull);
    });

    test('"use my location" that fails again changes nothing on screen', () async {
      final List<Map<String, dynamic>> calls = serveOffers(<Map<String, dynamic>>[Fx.offerRow('ph-1', 'pp-1')]);
      h.gps.failure = const AppFailure('location_off');
      final MedicineDetailsController c = make(where: noCache());
      await c.ensureOffers();
      final int before = calls.length;
      await c.useMyLocation();
      expect(calls.length, before);
      expect(c.where.error.value, 'err_location_off'.tr);
      expect(c.where.needsSettings.value, isTrue);
    });

    test('a failing offers request is an error state with the failure code', () async {
      h.api.rpcs['get_medicine_pharmacies'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final MedicineDetailsController c = make();
      await c.ensureOffers();
      expect(c.offers.status.value, ViewStatus.error);
      expect(c.offers.failure.value?.code, 'network');
    });

    test('an offer becomes a one-unit cart line at the price the pharmacy confirmed', () async {
      h.api.tables['medicines'] = <Map<String, dynamic>>[Fx.medicineRow('m1')];
      serveOffers(<Map<String, dynamic>>[Fx.offerRow('ph-1', 'pp-1', name: 'الشفاء', price: 4300)]);
      final MedicineDetailsController c = make();
      await c.reload();
      await c.ensureOffers();
      final MedicineOffer o = c.offers.items.single;
      final CartLine line = c.lineForOffer(o);
      expect(line.productId, 'pp-1');
      expect(line.unitPrice, 4300);
      expect(line.quantity, 1);
      expect(line.medicine.id, 'm1');
      final CartPharmacy target = c.targetForOffer(o);
      expect(target.id, 'ph-1');
      expect(target.name, 'الشفاء');
    });
  });

  group('ask the pharmacies nearby', () {
    setUp(() => h.api.rpcs['create_availability_request'] = (Map<String, dynamic> p) => Fx.requestJson('req-1'));

    test('creates the request from the current position, with a retry-safe key, and opens its screen', () async {
      h.gps.position = const GeoPoint(33.5102, 36.2765);
      final MedicineDetailsController c = make();
      final String? id = await c.askNearby();
      expect(id, 'req-1');
      final Map<String, dynamic> p = h.api.rpcLog.firstWhere((e) => e.fn == 'create_availability_request').params;
      expect(p['p_medicine_id'], 'm1');
      expect(p['p_latitude'], 33.5102);
      expect(p['p_longitude'], 36.2765);
      expect(p['p_idempotency_key'], startsWith('ask-'));
      expect(opened, <String>[AppRoutes.customerRequest('req-1')]);
      expect(c.starting, isFalse);
    });

    test('the first time it explains what happens; after that it does not ask again', () async {
      int asked = 0;
      Future<bool> counting({required String title, required String message, String? confirmLabel, bool destructive = false}) async {
        asked++;
        return true;
      }

      final MedicineDetailsController c = make(confirm: counting);
      await c.askNearby();
      await c.askNearby();
      expect(asked, 1);
      expect(AskNearbyIntro.seen, isTrue);
    });

    test('declining the explanation reads no position and sends nothing', () async {
      Future<bool> no({required String title, required String message, String? confirmLabel, bool destructive = false}) async => false;
      final MedicineDetailsController c = make(confirm: no);
      expect(await c.askNearby(), isNull);
      expect(h.gps.reads, 0);
      expect(h.api.rpcCount('create_availability_request'), 0);
      expect(AskNearbyIntro.seen, isFalse, reason: 'the customer has not understood it yet');
      expect(opened, isEmpty);
    });

    test('without a position nothing is sent and the reason is shown', () async {
      h.gps.failure = const AppFailure('location_denied_forever');
      final MedicineDetailsController c = make();
      expect(await c.askNearby(), isNull);
      expect(h.api.rpcCount('create_availability_request'), 0);
      expect(c.where.error.value, 'err_location_denied_forever'.tr);
      expect(c.where.needsSettings.value, isTrue);
      expect(opened, isEmpty);
    });

    test('a retry after a lost answer reuses the key; after success the next question gets a new one', () async {
      final List<Object?> keys = <Object?>[];
      bool first = true;
      h.api.rpcs['create_availability_request'] = (Map<String, dynamic> p) {
        keys.add(p['p_idempotency_key']);
        if (first) {
          first = false;
          throw const AppFailure('network');
        }
        return Fx.requestJson('req-1');
      };
      final MedicineDetailsController c = make();
      expect(await c.askNearby(), isNull);
      expect(c.failure.value?.code, 'network');
      expect(await c.askNearby(), 'req-1');
      expect(keys[0], keys[1]);
      await c.askNearby();
      expect(keys[2], isNot(keys[1]));
    });

    test('from another place it is another question: a new key', () async {
      final List<Object?> keys = <Object?>[];
      h.api.rpcs['create_availability_request'] = (Map<String, dynamic> p) {
        keys.add(p['p_idempotency_key']);
        throw const AppFailure('network');
      };
      final MedicineDetailsController c = make(where: noCache());
      await c.askNearby();
      h.gps.position = const GeoPoint(33.6, 36.4);
      await c.askNearby();
      expect(keys[0], isNot(keys[1]));
    });

    test('a few metres of GPS noise is the same place and keeps the key', () async {
      final List<Object?> keys = <Object?>[];
      h.api.rpcs['create_availability_request'] = (Map<String, dynamic> p) {
        keys.add(p['p_idempotency_key']);
        throw const AppFailure('network');
      };
      final MedicineDetailsController c = make(where: noCache());
      h.gps.position = const GeoPoint(33.51020, 36.27650);
      await c.askNearby();
      h.gps.position = const GeoPoint(33.51021, 36.27651);
      await c.askNearby();
      expect(keys[0], keys[1]);
    });

    test('too many requests is explained and nothing opens', () async {
      h.api.rpcs['create_availability_request'] = (Map<String, dynamic> p) => throw const AppFailure('too_many_requests');
      final MedicineDetailsController c = make();
      expect(await c.askNearby(), isNull);
      expect(c.failure.value?.code, 'too_many_requests');
      expect(opened, isEmpty);
    });

    test('a second tap while the first is running is ignored', () async {
      AskNearbyIntro.seen = true;
      h.api.delay = const Duration(milliseconds: 20);
      final MedicineDetailsController c = make();
      final Future<String?> a = c.askNearby();
      final Future<String?> b = c.askNearby();
      expect(await b, isNull);
      expect(await a, 'req-1');
      expect(h.api.rpcCount('create_availability_request'), 1);
      expect(opened.length, 1);
    });
  });

  group('PharmacyDetailsController', () {
    setUp(() {
      h.api.rpcs['get_public_pharmacy'] = (Map<String, dynamic> p) => publicPharmacyRow(p['p_pharmacy_id'] as String);
      serveCatalogue(h.api, <Map<String, dynamic>>[
        catalogueRow('p1', 'med-1'),
        catalogueRow('p2', 'med-2', ar: 'بروفين', en: 'Brufen', freshness: 'old'),
      ]);
    });

    PharmacyDetailsController makePharmacy([String id = 'ph-1']) => PharmacyDetailsController(id, cart: cart)..onInit();

    test('loads the pharmacy and its catalogue together', () async {
      final PharmacyDetailsController c = makePharmacy();
      await c.reload();
      expect(c.status.value, ViewStatus.ready);
      expect(c.pharmacy.value?.name, 'صيدلية الشفاء');
      expect(c.catalogue.items.length, 2);
      expect(c.cartTarget?.id, 'ph-1');
      expect(c.cartTarget?.currency, 'SYP');
    });

    test('every listed product can be added: there is no stock to run out', () async {
      final PharmacyDetailsController c = makePharmacy();
      await c.reload();
      for (final PublicProduct p in c.catalogue.items) {
        expect(cart.add(c.cartTarget!, CartLine.fromProduct(p)), CartAddResult.added);
      }
      expect(cart.lines.length, 2);
      expect(c.cartIsHere, isTrue);
    });

    test('a failing pharmacy request is an error state', () async {
      h.api.rpcs['get_public_pharmacy'] = (Map<String, dynamic> p) => throw const AppFailure('not_found');
      final PharmacyDetailsController c = makePharmacy();
      await c.reload();
      expect(c.status.value, ViewStatus.error);
      expect(c.failure.value?.code, 'not_found');
    });

    test('searching reloads the catalogue with the trimmed text and ignores an unchanged text', () async {
      final PharmacyDetailsController c = makePharmacy();
      await c.reload();
      await c.search('  بنادول ');
      expect(h.api.rpcLog.last.params['p_query'], 'بنادول');
      final int calls = h.api.rpcCount('get_public_pharmacy_products');
      await c.search('بنادول');
      expect(h.api.rpcCount('get_public_pharmacy_products'), calls);
    });

    test('cartIsHere is true only for the pharmacy whose items are in the cart', () async {
      final PharmacyDetailsController first = makePharmacy('ph-1');
      await first.reload();
      final PharmacyDetailsController second = makePharmacy('ph-2');
      await second.reload();
      cart.add(first.cartTarget!, CartLine.fromProduct(first.catalogue.items.first));
      expect(first.cartIsHere, isTrue);
      expect(second.cartIsHere, isFalse);
      expect(cart.add(second.cartTarget!, CartLine.fromProduct(second.catalogue.items.first)), CartAddResult.needsReplace);
    });

    test('before the pharmacy is loaded there is no cart target', () {
      expect(makePharmacy().cartTarget, isNull);
    });
  });
}
