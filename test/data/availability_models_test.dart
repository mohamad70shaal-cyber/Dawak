// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/data/models/availability.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../customer/customer_fixtures.dart';

AvailabilityRequest request({
  String status = 'open',
  int step = 1,
  int notified = 3,
  int answered = 0,
  int unavailable = 0,
  List<Map<String, dynamic>> offers = const <Map<String, dynamic>>[],
}) =>
    AvailabilityRequest.fromJson(
      Fx.requestJson('r1', status: status, step: step, notified: notified, answered: answered, unavailable: unavailable, offers: offers),
    );

void main() {
  group('RequestStatus / RequestAnswer / Freshness', () {
    test('status: unknown or missing words read as open; the label key follows the name', () {
      expect(RequestStatus.parse('closed'), RequestStatus.closed);
      expect(RequestStatus.parse('expired'), RequestStatus.expired);
      expect(RequestStatus.parse('open'), RequestStatus.open);
      expect(RequestStatus.parse(null), RequestStatus.open);
      expect(RequestStatus.parse('weird'), RequestStatus.open);
      expect(RequestStatus.closed.labelKey, 'req_status_closed');
      expect(RequestStatus.open.isOpen, isTrue);
      expect(RequestStatus.expired.isOpen, isFalse);
    });

    test('an answer is available, unavailable or nothing', () {
      expect(RequestAnswer.parse('available'), RequestAnswer.available);
      expect(RequestAnswer.parse('unavailable'), RequestAnswer.unavailable);
      expect(RequestAnswer.parse(null), isNull);
      expect(RequestAnswer.parse('maybe'), isNull);
    });

    test('freshness: only "recent" is recent; everything else means "not confirmed for a while"', () {
      expect(Freshness.parse('recent'), Freshness.recent);
      expect(Freshness.parse('old'), Freshness.old);
      expect(Freshness.parse(null), Freshness.old);
      expect(Freshness.parse('stale'), Freshness.old);
      expect(Freshness.recent.labelKey, 'fresh_recent');
      expect(Freshness.old.labelKey, 'fresh_old');
    });
  });

  group('AvailabilityRequest', () {
    test('the radius of each step is 1, 3, 5, 10 km and only the last one cannot widen', () {
      final List<AvailabilityRequest> all = <AvailabilityRequest>[for (int s = 1; s <= 4; s++) request(step: s)];
      expect(all.map((AvailabilityRequest r) => r.radiusKm), <double>[1, 3, 5, 10]);
      expect(all.map((AvailabilityRequest r) => r.radiusExhausted), <bool>[false, false, false, true]);
      expect(all.map((AvailabilityRequest r) => r.nextRadiusKm), <double?>[3, 5, 10, null]);
      expect(all.map((AvailabilityRequest r) => r.canSearchFurther), <bool>[true, true, true, false]);
      expect(AvailabilityRequest.radiiKm, <double>[1, 3, 5, 10]);
    });

    test('a request that is not open can never search further', () {
      expect(request(status: 'closed').canSearchFurther, isFalse);
      expect(request(status: 'expired', step: 2).canSearchFurther, isFalse);
    });

    test('waiting = asked but not answered, never negative', () {
      expect(request(notified: 3, answered: 1).waiting, 2);
      expect(request(notified: 3, answered: 3).waiting, 0);
      expect(request(notified: 1, answered: 2).waiting, 0);
    });

    test('nobodyInRange needs an empty circle at the largest radius', () {
      expect(request(step: 4, notified: 0).nobodyInRange, isTrue);
      expect(request(step: 3, notified: 0).nobodyInRange, isFalse, reason: 'it can still widen');
      expect(request(step: 4, notified: 2).nobodyInRange, isFalse);
    });

    test('allSaidNo needs everyone to have answered "no" at the largest radius', () {
      expect(request(step: 4, notified: 3, answered: 3, unavailable: 3).allSaidNo, isTrue);
      expect(request(step: 4, notified: 3, answered: 2, unavailable: 2).allSaidNo, isFalse, reason: 'one has not answered');
      expect(request(step: 3, notified: 3, answered: 3, unavailable: 3).allSaidNo, isFalse, reason: 'it can still widen');
      expect(
        request(step: 4, notified: 3, answered: 3, unavailable: 2, offers: <Map<String, dynamic>>[Fx.requestOfferRow('ph-1')]).allSaidNo,
        isFalse,
        reason: 'somebody said yes',
      );
    });

    test('offers carry the pharmacy, the price and the time of the answer', () {
      final AvailabilityRequest r = request(
        notified: 2,
        answered: 2,
        offers: <Map<String, dynamic>>[
          Fx.requestOfferRow('ph-1', name: 'الشفاء', price: 4200, distanceKm: 0.4, productId: 'prod-1'),
          Fx.requestOfferRow('ph-2', name: 'النور', price: 4500, distanceKm: 1.9, productId: null),
        ],
      );
      expect(r.hasOffers, isTrue);
      final AvailabilityOffer a = r.offers.first;
      expect(a.pharmacy.id, 'ph-1');
      expect(a.pharmacy.name, 'الشفاء');
      expect(a.price, 4200);
      expect(a.currency, 'SYP');
      expect(a.distanceKm, 0.4);
      expect(a.productId, 'prod-1');
      expect(a.answeredAt, isNotNull);
      expect(a.pharmacy.location, isNotNull);
      expect(r.offers.last.productId, isNull, reason: 'the pharmacy deleted its list row afterwards');
      expect(r.offers.last.distanceKm, 1.9);
    });

    test('a pharmacy that hides its phone has none in the answer', () {
      final Map<String, dynamic> row = Fx.requestOfferRow('ph-1')..['phone'] = null;
      final AvailabilityOffer o = AvailabilityOffer.fromJson(row);
      expect(o.pharmacy.phone, isNull);
    });

    test('the medicine and the counters are read as they come', () {
      final AvailabilityRequest r = request(notified: 5, answered: 3, unavailable: 2);
      expect(r.id, 'r1');
      expect(r.medicine.nameAr, 'بنادول');
      expect(r.notified, 5);
      expect(r.answered, 3);
      expect(r.unavailable, 2);
      expect(r.secondsLeft, 3600);
      expect(r.expiresAt, isNotNull);
    });

    test('a request that is not open has no seconds left', () {
      expect(request(status: 'expired').isOpen, isFalse);
      final Map<String, dynamic> json = Fx.requestJson('r1', status: 'expired')..['seconds_left'] = 0;
      expect(AvailabilityRequest.fromJson(json).secondsLeft, 0);
    });
  });

  group('AvailabilityRequestSummary', () {
    test('reads the history row: the medicine id comes from medicine_id', () {
      final AvailabilityRequestSummary s = AvailabilityRequestSummary.fromJson(summaryRow('r9', status: 'closed', offers: 2, medicineId: 'm7'));
      expect(s.id, 'r9');
      expect(s.medicine.id, 'm7');
      expect(s.medicine.nameAr, 'بنادول');
      expect(s.status, RequestStatus.closed);
      expect(s.offersCount, 2);
      expect(s.createdAt, isNotNull);
    });
  });

  group('InboxRequest', () {
    test('a request nobody at the pharmacy answered yet is waiting; an answered one is not', () {
      final InboxRequest open = InboxRequest.fromJson(Fx.inboxRow('r1'));
      expect(open.isOpen, isTrue);
      expect(open.isAnswered, isFalse);
      expect(open.isWaiting, isTrue);
      final InboxRequest done = InboxRequest.fromJson(Fx.inboxRow('r1', answer: 'available', answerPrice: 5000));
      expect(done.isAnswered, isTrue);
      expect(done.isWaiting, isFalse);
      expect(done.answer, RequestAnswer.available);
      expect(done.answerPrice, 5000);
    });

    test('a closed or expired request is never waiting, even unanswered', () {
      expect(InboxRequest.fromJson(Fx.inboxRow('r1', status: 'closed')).isWaiting, isFalse);
      expect(InboxRequest.fromJson(Fx.inboxRow('r1', status: 'expired')).isWaiting, isFalse);
    });

    test('remaining time counts down to zero and is null when not open', () {
      final InboxRequest r = InboxRequest.fromJson(Fx.inboxRow('r1'));
      final DateTime end = r.expiresAt!;
      expect(r.remaining(now: end.subtract(const Duration(minutes: 10)))?.inMinutes, 10);
      expect(r.remaining(now: end.add(const Duration(minutes: 1))), Duration.zero);
      expect(InboxRequest.fromJson(Fx.inboxRow('r1', status: 'closed')).remaining(), isNull);
    });

    test('the pharmacy\'s own list entry is carried to pre-fill the price', () {
      final InboxRequest r = InboxRequest.fromJson(Fx.inboxRow('r1', listedPrice: 4800, listedAvailable: true));
      expect(r.listedPrice, 4800);
      expect(r.listedAvailable, isTrue);
      final InboxRequest none = InboxRequest.fromJson(Fx.inboxRow('r1'));
      expect(none.listedPrice, isNull);
      expect(none.listedAvailable, isNull);
    });
  });

  group('catalogue and offers', () {
    test('PharmacyProduct freshness mirrors the server rule: a week', () {
      final DateTime now = DateTime(2026, 10, 20, 12);
      PharmacyProduct at(DateTime? confirmed, {bool available = true}) => PharmacyProduct.fromJson(<String, dynamic>{
            'id': 'p1',
            'pharmacy_id': 'ph-1',
            'medicine_id': 'm1',
            'medicines': Fx.medicineRow('m1'),
            'price': 5000,
            'is_available': available,
            'confirmed_at': confirmed?.toUtc().toIso8601String(),
          });
      expect(at(now.subtract(const Duration(days: 6))).freshness(now: now), Freshness.recent);
      expect(at(now.subtract(const Duration(days: 8))).freshness(now: now), Freshness.old);
      expect(at(null).freshness(now: now), Freshness.old);
      expect(at(now.subtract(const Duration(days: 8))).isStale(now: now), isTrue);
      expect(at(now.subtract(const Duration(days: 8)), available: false).isStale(now: now), isFalse, reason: 'unavailable rows are not "stale"');
      expect(at(now.subtract(const Duration(days: 1))).isStale(now: now), isFalse);
    });

    test('MedicineOffer reads the pharmacy, the price, the distance and the confirmation', () {
      final MedicineOffer o = MedicineOffer.fromJson(Fx.offerRow('ph-1', 'pp-1', name: 'الشفاء', price: 4300, distanceKm: 0.7, freshness: 'old'));
      expect(o.pharmacy.id, 'ph-1');
      expect(o.pharmacy.name, 'الشفاء');
      expect(o.productId, 'pp-1');
      expect(o.price, 4300);
      expect(o.distanceKm, 0.7);
      expect(o.freshness, Freshness.old);
      expect(o.confirmedAt, isNotNull);
    });

    test('an offer without a position has no distance', () {
      expect(MedicineOffer.fromJson(Fx.offerRow('ph-1', 'pp-1')).distanceKm, isNull);
    });

    test('PublicProduct reads the medicine from the flat row', () {
      final PublicProduct p = PublicProduct.fromJson(catalogueRow('pp-1', 'm9', price: 3100, freshness: 'old'));
      expect(p.productId, 'pp-1');
      expect(p.medicine.id, 'm9');
      expect(p.medicine.nameAr, 'بنادول');
      expect(p.price, 3100);
      expect(p.freshness, Freshness.old);
    });

    test('ImportResult adds up and counts only what was saved', () {
      const ImportResult a = ImportResult(inserted: 3, updated: 2, skipped: 1);
      const ImportResult b = ImportResult(inserted: 1, updated: 0, skipped: 4);
      final ImportResult c = a + b;
      expect(c.inserted, 4);
      expect(c.updated, 2);
      expect(c.skipped, 5);
      expect(c.saved, 6);
      expect(ImportResult.zero.saved, 0);
      expect(ImportResult.fromJson(<String, dynamic>{'inserted': 2, 'updated': 1}).skipped, 0);
    });
  });
}
