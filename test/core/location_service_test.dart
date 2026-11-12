// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/core/services/location_service.dart';
import 'package:dawak/data/models/geo.dart';
import 'package:dawak/features/customer/controllers/customer_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_api.dart';
import '../support/harness.dart';

void main() {
  group('LocationService', () {
    late FakeLocationGateway gps;
    late DateTime now;
    late LocationService service;

    setUp(() {
      gps = FakeLocationGateway();
      now = DateTime(2026, 10, 10, 12);
      service = LocationService(gps, freshFor: const Duration(minutes: 5), clock: () => now);
    });

    test('the first call reads the GPS and remembers the position', () async {
      final GeoPoint p = await service.locate();
      expect(p, gps.position);
      expect(service.lastKnown.value, gps.position);
      expect(gps.reads, 1);
    });

    test('a position younger than freshFor is reused without touching the GPS', () async {
      await service.locate();
      now = now.add(const Duration(minutes: 4));
      await service.locate();
      expect(gps.reads, 1);
    });

    test('an older position is read again', () async {
      await service.locate();
      now = now.add(const Duration(minutes: 6));
      gps.position = const GeoPoint(33.6, 36.4);
      final GeoPoint p = await service.locate();
      expect(gps.reads, 2);
      expect(p.latitude, 33.6);
    });

    test('forceFresh always reads again', () async {
      await service.locate();
      await service.locate(forceFresh: true);
      expect(gps.reads, 2);
    });

    test('a failure is thrown as an AppFailure and nothing is remembered', () async {
      gps.failure = const AppFailure('location_off');
      await expectLater(service.locate(), throwsA(isA<AppFailure>().having((AppFailure f) => f.code, 'code', 'location_off')));
      expect(service.lastKnown.value, isNull);
      gps.failure = null;
      expect(await service.locate(), gps.position);
      expect(gps.reads, 2, reason: 'the failed read was not cached');
    });

    test('a failure after a success keeps the last known position for display, but a new read is still attempted', () async {
      await service.locate();
      gps.failure = const AppFailure('location_timeout');
      await expectLater(service.locate(forceFresh: true), throwsA(isA<AppFailure>()));
      expect(service.lastKnown.value, isNotNull);
    });

    test('forget clears the remembered position (sign-out)', () async {
      await service.locate();
      service.forget();
      expect(service.lastKnown.value, isNull);
      await service.locate();
      expect(gps.reads, 2);
    });

    test('openSettings is passed to the system', () async {
      await service.openSettings();
      expect(gps.settingsOpened, 1);
    });
  });

  group('CustomerLocation', () {
    late AppHarness h;
    late CustomerLocation where;

    setUp(() async {
      h = await AppHarness.create();
      where = CustomerLocation(service: LocationService(h.gps, freshFor: Duration.zero));
    });
    tearDown(() => h.dispose());

    test('a successful read sets the point and clears an old message', () async {
      where.error.value = 'old';
      where.needsSettings.value = true;
      h.gps.position = const GeoPoint(33.5102, 36.2765);
      final GeoPoint? p = await where.locate();
      expect(p, const GeoPoint(33.5102, 36.2765));
      expect(where.point.value, p);
      expect(where.error.value, isNull);
      expect(where.needsSettings.value, isFalse);
      expect(where.locating.value, isFalse);
    });

    test('locating is true while the read runs', () async {
      final Future<GeoPoint?> f = where.locate();
      expect(where.locating.value, isTrue);
      await f;
      expect(where.locating.value, isFalse);
    });

    test('several callers at once share one read and get the same answer', () async {
      final List<GeoPoint?> r = await Future.wait<GeoPoint?>(<Future<GeoPoint?>>[where.locate(), where.locate(), where.locate()]);
      expect(h.gps.reads, 1);
      expect(r.toSet().length, 1);
    });

    test('a failure never throws: it gives null and a translated reason', () async {
      h.gps.failure = const AppFailure('location_denied');
      expect(await where.locate(), isNull);
      expect(where.error.value, 'err_location_denied'.tr);
      expect(where.needsSettings.value, isFalse);
      expect(where.locating.value, isFalse);
    });

    test('only "location off" and "blocked for good" send the customer to the settings', () async {
      for (final String code in <String>['location_off', 'location_denied_forever']) {
        h.gps.failure = AppFailure(code);
        await where.locate();
        expect(where.needsSettings.value, isTrue, reason: code);
      }
      for (final String code in <String>['location_denied', 'location_timeout', 'location_unavailable']) {
        h.gps.failure = AppFailure(code);
        await where.locate();
        expect(where.needsSettings.value, isFalse, reason: code);
      }
    });

    test('a failure keeps the last position the screen had', () async {
      final GeoPoint? first = await where.locate();
      h.gps.failure = const AppFailure('location_timeout');
      await where.locate();
      expect(where.point.value, first);
    });

    test('after a failure the next success clears the message', () async {
      h.gps.failure = const AppFailure('location_off');
      await where.locate();
      h.gps.failure = null;
      await where.locate();
      expect(where.error.value, isNull);
      expect(where.needsSettings.value, isFalse);
    });

    test('clearError and openSettings', () async {
      h.gps.failure = const AppFailure('location_off');
      await where.locate();
      where.clearError();
      expect(where.error.value, isNull);
      expect(where.needsSettings.value, isFalse);
      await where.openSettings();
      expect(h.gps.settingsOpened, 1);
    });
  });
}
