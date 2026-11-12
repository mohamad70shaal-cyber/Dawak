// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/base/base_controller.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/availability.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/features/customer/controllers/availability_request_controller.dart';
import 'package:dawak/features/customer/controllers/cart_controller.dart';
import 'package:dawak/features/customer/services/customer_dialog_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';

void main() {
  late AppHarness h;
  late CartController cart;
  late List<String> opened;
  late List<AvailabilityRequestController> made;
  late List<Map<String, dynamic>> served; // the states the "server" returns, in order; the last one repeats

  setUp(() async {
    h = await AppHarness.create();
    cart = Get.put<CartController>(CartController());
    opened = <String>[];
    made = <AvailabilityRequestController>[];
    served = <Map<String, dynamic>>[Fx.requestJson('req-1')];
    h.api.rpcs['get_availability_request'] = (Map<String, dynamic> p) {
      final Map<String, dynamic> r = served.length > 1 ? served.removeAt(0) : served.first;
      return r;
    };
  });
  tearDown(() {
    for (final AvailabilityRequestController c in made) {
      c.onClose();
    }
    h.dispose();
  });

  Future<bool> yes({required String title, required String message, String? confirmLabel, bool destructive = false}) async => true;
  Future<bool> no({required String title, required String message, String? confirmLabel, bool destructive = false}) async => false;

  AvailabilityRequestController make({CustomerConfirmFn? confirm, Duration every = const Duration(hours: 1)}) {
    final AvailabilityRequestController c =
        AvailabilityRequestController('req-1', cart: cart, confirm: confirm ?? yes, open: opened.add, pollEvery: every)..onInit();
    made.add(c);
    return c;
  }

  Map<String, dynamic> offer(String pharmacyId, {double price = 5000, String? productId = 'prod-1'}) =>
      Fx.requestOfferRow(pharmacyId, price: price, productId: productId);

  group('loading', () {
    test('shows the request as the server describes it', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', notified: 3, answered: 1)];
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(c.status.value, ViewStatus.ready);
      expect(c.request.value?.notified, 3);
      expect(c.request.value?.answered, 1);
      expect(c.offline.value, isFalse);
    });

    test('a request that is not the customer\'s (or no longer exists) is a not_found error', () async {
      h.api.rpcs['get_availability_request'] = (Map<String, dynamic> p) => throw const AppFailure('not_found');
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(c.status.value, ViewStatus.error);
      expect(c.failure.value?.code, 'not_found');
    });
  });

  group('phase: the one sentence that says where the request stands', () {
    Future<RequestPhase> phaseOf(Map<String, dynamic> json) async {
      served = <Map<String, dynamic>>[json];
      final AvailabilityRequestController c = make();
      await c.reload();
      return c.phase;
    }

    test('open, nobody has answered yet: waiting', () async {
      expect(await phaseOf(Fx.requestJson('req-1', notified: 3, answered: 0)), RequestPhase.waiting);
    });

    test('open, the circle is empty but can still widen: waiting (the server widens by itself)', () async {
      expect(await phaseOf(Fx.requestJson('req-1', step: 1, notified: 0)), RequestPhase.waiting);
    });

    test('open, everybody asked said no but there is further to look: still waiting', () async {
      expect(await phaseOf(Fx.requestJson('req-1', step: 2, notified: 2, answered: 2, unavailable: 2)), RequestPhase.waiting);
    });

    test('open with at least one yes: hasOffers', () async {
      expect(
        await phaseOf(Fx.requestJson('req-1', notified: 2, answered: 1, offers: <Map<String, dynamic>>[offer('ph-1')])),
        RequestPhase.hasOffers,
      );
    });

    test('open at the largest radius with nobody in range: nobodyInRange', () async {
      expect(await phaseOf(Fx.requestJson('req-1', step: 4, notified: 0)), RequestPhase.nobodyInRange);
    });

    test('open at the largest radius and every answer is no: allSaidNo', () async {
      expect(await phaseOf(Fx.requestJson('req-1', step: 4, notified: 3, answered: 3, unavailable: 3)), RequestPhase.allSaidNo);
    });

    test('at the largest radius with some pharmacies still silent it keeps waiting', () async {
      expect(await phaseOf(Fx.requestJson('req-1', step: 4, notified: 3, answered: 2, unavailable: 2)), RequestPhase.waiting);
    });

    test('expired and closed override everything, offers or not', () async {
      expect(await phaseOf(Fx.requestJson('req-1', status: 'expired', offers: <Map<String, dynamic>>[offer('ph-1')])), RequestPhase.expired);
      expect(await phaseOf(Fx.requestJson('req-1', status: 'closed')), RequestPhase.closed);
    });
  });

  group('polling', () {
    test('a poll puts the newest answers on screen', () async {
      served = <Map<String, dynamic>>[
        Fx.requestJson('req-1', notified: 2),
        Fx.requestJson('req-1', notified: 2, answered: 1, offers: <Map<String, dynamic>>[offer('ph-1')]),
      ];
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(c.request.value?.hasOffers, isFalse);
      await c.poll();
      expect(c.request.value?.offers.single.pharmacy.id, 'ph-1');
      expect(c.phase, RequestPhase.hasOffers);
    });

    test('the timer polls by itself while the request is open', () async {
      final AvailabilityRequestController c = make(every: const Duration(milliseconds: 15));
      await c.reload();
      final int afterLoad = h.api.rpcCount('get_availability_request');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(h.api.rpcCount('get_availability_request'), greaterThan(afterLoad));
    });

    test('polling stops once the request is no longer open', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1'), Fx.requestJson('req-1', status: 'expired')];
      final AvailabilityRequestController c = make(every: const Duration(milliseconds: 15));
      await c.reload();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final int settled = h.api.rpcCount('get_availability_request');
      expect(c.request.value?.status, RequestStatus.expired);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h.api.rpcCount('get_availability_request'), settled, reason: 'no reads after expiry');
    });

    test('a request that is already closed never starts polling', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', status: 'closed')];
      final AvailabilityRequestController c = make(every: const Duration(milliseconds: 15));
      await c.reload();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h.api.rpcCount('get_availability_request'), 1);
    });

    test('a failed poll keeps the last answer on screen and only marks it as possibly old; the next good poll clears the mark', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', notified: 2, answered: 1, offers: <Map<String, dynamic>>[offer('ph-1')])];
      final AvailabilityRequestController c = make();
      await c.reload();
      h.api.failNext('rpc:get_availability_request', const AppFailure('network'));
      await c.poll();
      expect(c.offline.value, isTrue);
      expect(c.request.value?.offers.length, 1, reason: 'what the customer already has stays');
      expect(c.status.value, ViewStatus.ready);
      expect(c.failure.value, isNull);
      await c.poll();
      expect(c.offline.value, isFalse);
    });

    test('a poll that finds the request gone turns the screen into a not_found error and stops polling', () async {
      final AvailabilityRequestController c = make(every: const Duration(milliseconds: 15));
      await c.reload();
      h.api.rpcs['get_availability_request'] = (Map<String, dynamic> p) => throw const AppFailure('not_found');
      await c.poll();
      expect(c.status.value, ViewStatus.error);
      expect(c.failure.value?.code, 'not_found');
      final int n = h.api.rpcCount('get_availability_request');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h.api.rpcCount('get_availability_request'), n);
    });

    test('two polls at once make one call', () async {
      final AvailabilityRequestController c = make();
      await c.reload();
      h.api.delay = const Duration(milliseconds: 20);
      final int before = h.api.rpcCount('get_availability_request');
      await Future.wait<void>(<Future<void>>[c.poll(), c.poll()]);
      expect(h.api.rpcCount('get_availability_request') - before, 1);
    });

    test('the radius growing by itself is announced; a manual widening is not', () async {
      served = <Map<String, dynamic>>[
        Fx.requestJson('req-1', step: 1),
        Fx.requestJson('req-1', step: 2),
      ];
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(c.grewTo.value, isNull, reason: 'the first read announces nothing');
      await c.poll();
      expect(c.grewTo.value, 3);
      c.dismissGrowth();
      expect(c.grewTo.value, isNull);
    });

    test('a poll never changes the radius announcement when the radius stayed the same', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', step: 2)];
      final AvailabilityRequestController c = make();
      await c.reload();
      await c.poll();
      expect(c.grewTo.value, isNull);
    });
  });

  group('time left', () {
    test('comes from the server and counts down from the moment of the read', () async {
      served = <Map<String, dynamic>>[
        <String, dynamic>{...Fx.requestJson('req-1'), 'seconds_left': 600},
      ];
      final AvailabilityRequestController c = make();
      await c.reload();
      final Duration? left = c.remaining;
      expect(left, isNotNull);
      expect(left!.inSeconds, inInclusiveRange(598, 600));
    });

    test('is null when the request is not open', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', status: 'expired')];
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(c.remaining, isNull);
    });
  });

  group('search further', () {
    test('widens one step now, shows the new radius and does not announce it as a surprise', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', step: 1)];
      h.api.rpcs['expand_availability_request'] = (Map<String, dynamic> p) => Fx.requestJson('req-1', step: 2, notified: 5);
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(c.request.value?.nextRadiusKm, 3);
      expect(await c.expand(), isTrue);
      expect(c.request.value?.radiusKm, 3);
      expect(c.request.value?.notified, 5);
      expect(c.grewTo.value, isNull);
      expect(h.api.rpcLog.firstWhere((e) => e.fn == 'expand_availability_request').params['p_request_id'], 'req-1');
    });

    test('is not offered (and sends nothing) at the largest radius', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', step: 4)];
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(c.request.value?.canSearchFurther, isFalse);
      expect(c.request.value?.nextRadiusKm, isNull);
      expect(await c.expand(), isFalse);
      expect(h.api.rpcCount('expand_availability_request'), 0);
    });

    test('is not offered on a request that is closed', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', status: 'closed')];
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(await c.expand(), isFalse);
      expect(h.api.rpcCount('expand_availability_request'), 0);
    });

    test('after a refusal the screen is re-read, because it was out of date', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', step: 1), Fx.requestJson('req-1', status: 'closed')];
      h.api.rpcs['expand_availability_request'] = (Map<String, dynamic> p) => throw const AppFailure('request_closed');
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(await c.expand(), isFalse);
      expect(c.request.value?.status, RequestStatus.closed);
      expect(h.api.rpcCount('get_availability_request'), 2, reason: 'one read to open the screen, one after the refusal');
    });

    test('a double tap sends one request', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', step: 1)];
      h.api.rpcs['expand_availability_request'] = (Map<String, dynamic> p) => Fx.requestJson('req-1', step: 2);
      final AvailabilityRequestController c = make();
      await c.reload();
      h.api.delay = const Duration(milliseconds: 20);
      final Future<bool> a = c.expand();
      final Future<bool> b = c.expand();
      expect(await b, isFalse);
      expect(await a, isTrue);
      expect(h.api.rpcCount('expand_availability_request'), 1);
    });

    test('a poll that started before the widening cannot put the older state back', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', step: 1)];
      h.api.rpcs['expand_availability_request'] = (Map<String, dynamic> p) => Fx.requestJson('req-1', step: 2);
      final AvailabilityRequestController c = make();
      await c.reload();
      h.api.delay = const Duration(milliseconds: 30);
      final Future<void> slowPoll = c.poll(); // reads step 1 ...
      h.api.delay = Duration.zero;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await c.expand(); // ... while the customer widens to step 2
      await slowPoll;
      expect(c.request.value?.step, 2);
    });
  });

  group('close', () {
    test('asks first; "no" changes nothing', () async {
      final AvailabilityRequestController c = make(confirm: no);
      await c.reload();
      expect(await c.closeRequest(), isFalse);
      expect(h.api.rpcCount('close_availability_request'), 0);
      expect(c.request.value?.isOpen, isTrue);
    });

    test('"yes" closes it, the screen shows the closed request and polling stops', () async {
      h.api.rpcs['close_availability_request'] = (Map<String, dynamic> p) => Fx.requestJson('req-1', status: 'closed');
      final AvailabilityRequestController c = make(every: const Duration(milliseconds: 15));
      await c.reload();
      expect(await c.closeRequest(), isTrue);
      expect(c.phase, RequestPhase.closed);
      final int n = h.api.rpcCount('get_availability_request');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h.api.rpcCount('get_availability_request'), n);
    });

    test('a request that is not open cannot be closed again', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', status: 'expired')];
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(await c.closeRequest(), isFalse);
      expect(h.api.rpcCount('close_availability_request'), 0);
    });

    test('a server refusal is explained and the screen re-reads the truth', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1'), Fx.requestJson('req-1', status: 'expired')];
      h.api.rpcs['close_availability_request'] = (Map<String, dynamic> p) => throw const AppFailure('request_closed');
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(await c.closeRequest(), isFalse);
      expect(c.request.value?.status, RequestStatus.expired);
    });
  });

  group('reserving an answer', () {
    test('an answer with a list row becomes a one-unit cart line at the answered price', () async {
      served = <Map<String, dynamic>>[
        Fx.requestJson('req-1', notified: 1, answered: 1, offers: <Map<String, dynamic>>[offer('ph-1', price: 4200, productId: 'prod-9')]),
      ];
      final AvailabilityRequestController c = make();
      await c.reload();
      final AvailabilityOffer o = c.request.value!.offers.single;
      final CartLine? line = c.lineFor(o);
      expect(line, isNotNull);
      expect(line!.productId, 'prod-9');
      expect(line.unitPrice, 4200);
      expect(line.medicine.id, 'med-1');
      expect(c.targetFor(o).id, 'ph-1');
      expect(c.targetFor(o).currency, 'SYP');
    });

    test('an answer whose list row is gone cannot be reserved', () async {
      served = <Map<String, dynamic>>[
        Fx.requestJson('req-1', notified: 1, answered: 1, offers: <Map<String, dynamic>>[offer('ph-1', productId: null)]),
      ];
      final AvailabilityRequestController c = make();
      await c.reload();
      expect(c.lineFor(c.request.value!.offers.single), isNull);
    });
  });

  group('navigation', () {
    test('"ask again" opens the medicine, where a new question can be started', () async {
      served = <Map<String, dynamic>>[Fx.requestJson('req-1', status: 'expired')];
      final AvailabilityRequestController c = make();
      await c.reload();
      c.openMedicine();
      expect(opened, <String>[AppRoutes.medicine('med-1')]);
    });

    test('tapping a pharmacy opens its page', () async {
      served = <Map<String, dynamic>>[
        Fx.requestJson('req-1', notified: 1, answered: 1, offers: <Map<String, dynamic>>[offer('ph-7')]),
      ];
      final AvailabilityRequestController c = make();
      await c.reload();
      c.openPharmacy(c.request.value!.offers.single);
      expect(opened, <String>[AppRoutes.pharmacy('ph-7')]);
    });

    test('before the request is loaded there is nothing to open', () {
      final AvailabilityRequestController c = make();
      c.openMedicine();
      expect(opened, isEmpty);
    });
  });
}
