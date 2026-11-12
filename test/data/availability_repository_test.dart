// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/availability.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/data/models/geo.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/data/repositories/availability_repository.dart';
import 'package:dawak/data/repositories/medicine_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import '../customer/customer_fixtures.dart';

void main() {
  late AppHarness h;
  late AvailabilityRepository repo;
  setUp(() async {
    h = await AppHarness.create();
    repo = Get.find<AvailabilityRepository>();
  });
  tearDown(() => h.dispose());

  Map<String, dynamic> lastParams(String fn) => h.api.rpcLog.lastWhere((e) => e.fn == fn).params;

  group('customer calls', () {
    test('create sends the medicine, the position and the idempotency key, and reads the request', () async {
      h.api.rpcs['create_availability_request'] = (Map<String, dynamic> p) => Fx.requestJson('r1', notified: 4);
      final AvailabilityRequest r = await repo.create(medicineId: 'm1', from: const GeoPoint(33.5102, 36.2765), idempotencyKey: 'ask-abc12345');
      expect(lastParams('create_availability_request'), <String, dynamic>{
        'p_medicine_id': 'm1',
        'p_latitude': 33.5102,
        'p_longitude': 36.2765,
        'p_idempotency_key': 'ask-abc12345',
      });
      expect(r.id, 'r1');
      expect(r.notified, 4);
    });

    test('get, expand and close address the request by id', () async {
      h.api.rpcs['get_availability_request'] = (Map<String, dynamic> p) => Fx.requestJson(p['p_request_id'] as String);
      h.api.rpcs['expand_availability_request'] = (Map<String, dynamic> p) => Fx.requestJson(p['p_request_id'] as String, step: 2);
      h.api.rpcs['close_availability_request'] = (Map<String, dynamic> p) => Fx.requestJson(p['p_request_id'] as String, status: 'closed');
      expect((await repo.get('r1')).id, 'r1');
      expect((await repo.expand('r2')).radiusKm, 3);
      expect((await repo.close('r3')).status, RequestStatus.closed);
      expect(lastParams('get_availability_request'), <String, dynamic>{'p_request_id': 'r1'});
      expect(lastParams('expand_availability_request'), <String, dynamic>{'p_request_id': 'r2'});
      expect(lastParams('close_availability_request'), <String, dynamic>{'p_request_id': 'r3'});
    });

    test('mine reads the history and pages with limit and offset', () async {
      h.api.rpcs['list_my_availability_requests'] = (Map<String, dynamic> p) => <Map<String, dynamic>>[
            summaryRow('r1', offers: 2),
            summaryRow('r2', status: 'expired'),
          ];
      final List<AvailabilityRequestSummary> l = await repo.mine(limit: 5, offset: 10);
      expect(l.map((AvailabilityRequestSummary s) => s.id), <String>['r1', 'r2']);
      expect(l.first.offersCount, 2);
      expect(lastParams('list_my_availability_requests'), <String, dynamic>{'p_limit': 5, 'p_offset': 10});
    });

    test('server refusals reach the caller as the AppFailure they are', () async {
      h.api.failNext('rpc:create_availability_request', const AppFailure('too_many_requests'));
      await expectLater(
        repo.create(medicineId: 'm1', from: const GeoPoint(33.5, 36.2), idempotencyKey: 'ask-abc12345'),
        throwsA(isA<AppFailure>().having((AppFailure f) => f.code, 'code', 'too_many_requests')),
      );
      h.api.failNext('rpc:expand_availability_request', const AppFailure('invalid_transition'));
      await expectLater(repo.expand('r1'), throwsA(isA<AppFailure>().having((AppFailure f) => f.code, 'code', 'invalid_transition')));
    });
  });

  group('pharmacy calls', () {
    test('openCount asks for one pharmacy and returns the number', () async {
      h.api.rpcs['count_pharmacy_availability_requests'] = (Map<String, dynamic> p) => 4;
      expect(await repo.openCount('ph-1'), 4);
      expect(lastParams('count_pharmacy_availability_requests'), <String, dynamic>{'p_pharmacy_id': 'ph-1'});
    });

    test('inbox sends the filter and the paging and reads the rows', () async {
      h.api.rpcs['list_pharmacy_availability_requests'] = (Map<String, dynamic> p) => <Map<String, dynamic>>[
            Fx.inboxRow('r1'),
            Fx.inboxRow('r2', answer: 'unavailable'),
          ];
      final List<InboxRequest> l = await repo.inbox('ph-1', onlyOpen: false, limit: 10, offset: 20);
      expect(l.map((InboxRequest r) => r.requestId), <String>['r1', 'r2']);
      expect(l.last.answer, RequestAnswer.unavailable);
      expect(lastParams('list_pharmacy_availability_requests'), <String, dynamic>{
        'p_pharmacy_id': 'ph-1',
        'p_only_open': false,
        'p_limit': 10,
        'p_offset': 20,
      });
    });

    test('inbox defaults to the live (open) list', () async {
      h.api.rpcs['list_pharmacy_availability_requests'] = (Map<String, dynamic> p) => <Map<String, dynamic>>[];
      await repo.inbox('ph-1');
      expect(lastParams('list_pharmacy_availability_requests')['p_only_open'], true);
    });

    test('"available" sends the price', () async {
      h.api.rpcs['answer_availability_request'] = (Map<String, dynamic> p) => <String, dynamic>{};
      await repo.answer(pharmacyId: 'ph-1', requestId: 'r1', available: true, price: 4800);
      expect(lastParams('answer_availability_request'), <String, dynamic>{
        'p_pharmacy_id': 'ph-1',
        'p_request_id': 'r1',
        'p_available': true,
        'p_price': 4800,
      });
    });

    test('"unavailable" never sends a price, even when one is given', () async {
      h.api.rpcs['answer_availability_request'] = (Map<String, dynamic> p) => <String, dynamic>{};
      await repo.answer(pharmacyId: 'ph-1', requestId: 'r1', available: false, price: 4800);
      expect(lastParams('answer_availability_request')['p_available'], false);
      expect(lastParams('answer_availability_request')['p_price'], isNull);
    });
  });

  group('MedicineRepository.offers', () {
    late MedicineRepository medicines;
    setUp(() {
      medicines = Get.find<MedicineRepository>();
      h.api.rpcs['get_medicine_pharmacies'] = (Map<String, dynamic> p) => <Map<String, dynamic>>[Fx.offerRow('ph-1', 'pp-1', distanceKm: 0.5)];
    });

    test('with a position it sends it, and the radius when asked for', () async {
      final List<MedicineOffer> l = await medicines.offers('m1', near: const GeoPoint(33.5, 36.2), radiusKm: 3, limit: 10, offset: 5);
      expect(l.single.distanceKm, 0.5);
      expect(lastParams('get_medicine_pharmacies'), <String, dynamic>{
        'p_medicine_id': 'm1',
        'p_latitude': 33.5,
        'p_longitude': 36.2,
        'p_radius_km': 3.0,
        'p_city': null,
        'p_limit': 10,
        'p_offset': 5,
      });
    });

    test('without a position no coordinates are sent and a radius is ignored (the server would refuse it)', () async {
      await medicines.offers('m1', radiusKm: 3);
      final Map<String, dynamic> p = lastParams('get_medicine_pharmacies');
      expect(p['p_latitude'], isNull);
      expect(p['p_longitude'], isNull);
      expect(p['p_radius_km'], isNull);
    });

    test('a blank city is not a filter; a city is trimmed', () async {
      await medicines.offers('m1', city: '   ');
      expect(lastParams('get_medicine_pharmacies')['p_city'], isNull);
      await medicines.offers('m1', city: ' دمشق ');
      expect(lastParams('get_medicine_pharmacies')['p_city'], 'دمشق');
    });
  });
}
