// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/geo.dart';
import 'package:dawak/features/pharmacist/controllers/shop_location_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/harness.dart';

void main() {
  late AppHarness h;
  late ShopLocationInput input;

  setUp(() async {
    h = await AppHarness.create();
    input = ShopLocationInput();
  });
  tearDown(() {
    input.dispose();
    h.dispose();
  });

  group('reading the GPS', () {
    test('a successful read sets the point, clears the paste field and any old message', () async {
      input.paste.text = 'old text';
      input.error.value = 'old error';
      input.needsSettings.value = true;
      h.gps.position = const GeoPoint(33.5102, 36.2765);

      expect(await input.useCurrent(), isTrue);

      expect(input.point.value?.latitude, 33.5102);
      expect(input.point.value?.longitude, 36.2765);
      expect(input.paste.text, '');
      expect(input.error.value, isNull);
      expect(input.needsSettings.value, isFalse);
      expect(input.locating.value, isFalse);
    });

    test('every tap reads the GPS again (a fresh fix, not the remembered one)', () async {
      await input.useCurrent();
      h.gps.position = const GeoPoint(33.6, 36.4);
      await input.useCurrent();
      expect(h.gps.reads, 2);
      expect(input.point.value?.latitude, 33.6);
    });

    test('a second tap while the first read is running is ignored', () async {
      final Future<bool> first = input.useCurrent();
      expect(input.locating.value, isTrue);
      expect(await input.useCurrent(), isFalse);
      expect(await first, isTrue);
      expect(h.gps.reads, 1);
    });

    test('location switched off or blocked for the app: the message says so and offers the settings', () async {
      for (final String code in <String>['location_off', 'location_denied_forever']) {
        h.gps.failure = AppFailure(code);
        expect(await input.useCurrent(), isFalse, reason: code);
        expect(input.error.value, 'err_$code'.tr, reason: code);
        expect(input.needsSettings.value, isTrue, reason: code);
      }
    });

    test('permission refused once, a timeout or no fix: the message is shown, the settings are not offered', () async {
      for (final String code in <String>['location_denied', 'location_timeout', 'location_unavailable']) {
        h.gps.failure = AppFailure(code);
        expect(await input.useCurrent(), isFalse, reason: code);
        expect(input.error.value, 'err_$code'.tr, reason: code);
        expect(input.needsSettings.value, isFalse, reason: code);
      }
    });

    test('a failure keeps the position that was chosen before', () async {
      await input.useCurrent();
      final GeoPoint? before = input.point.value;
      h.gps.failure = const AppFailure('location_timeout');
      expect(await input.useCurrent(), isFalse);
      expect(input.point.value, same(before));
    });

    test('a read that works after a failure clears the failure', () async {
      h.gps.failure = const AppFailure('location_off');
      await input.useCurrent();
      h.gps.failure = null;
      expect(await input.useCurrent(), isTrue);
      expect(input.error.value, isNull);
      expect(input.needsSettings.value, isFalse);
    });

    test('openSettings asks the system to open its settings page', () async {
      await input.openSettings();
      expect(h.gps.settingsOpened, 1);
    });
  });

  group('a pasted link or coordinates', () {
    test('plain coordinates, Arabic digits and a Google Maps link are all accepted', () {
      input.paste.text = '33.5102, 36.2765';
      expect(input.usePasted(), isTrue);
      expect(input.point.value?.latitude, 33.5102);

      input.paste.text = '٣٣٫٥٠٠١، ٣٦٫٣٠٠٢';
      expect(input.usePasted(), isTrue);
      expect(input.point.value?.latitude, 33.5001);
      expect(input.point.value?.longitude, 36.3002);

      input.paste.text = 'https://www.google.com/maps/place/Shop/@33.4,36.2,17z/data=!3m1';
      expect(input.usePasted(), isTrue);
      expect(input.point.value?.latitude, 33.4);
      expect(input.error.value, isNull);
    });

    test('text without coordinates says so and keeps the earlier position', () {
      input.setInitial(const GeoPoint(33.5, 36.3));
      input.paste.text = 'قرب جامع المزة';
      expect(input.usePasted(), isFalse);
      expect(input.error.value, 'p_loc_paste_invalid'.tr);
      expect(input.point.value?.latitude, 33.5);
    });

    test('a short share link gets its own explanation', () {
      input.paste.text = 'https://maps.app.goo.gl/AbCdEf123';
      expect(input.usePasted(), isFalse);
      expect(input.error.value, 'p_loc_short_link'.tr);
    });

    test('the null island (0, 0) and out-of-range numbers are refused', () {
      input.paste.text = '0, 0';
      expect(input.usePasted(), isFalse);
      input.paste.text = '95.2, 36.2';
      expect(input.usePasted(), isFalse);
      expect(input.point.value, isNull);
    });

    test('a usable paste after a failed one clears the message', () {
      input.paste.text = 'nonsense';
      input.usePasted();
      expect(input.error.value, isNotNull);
      input.paste.text = '33.5, 36.3';
      expect(input.usePasted(), isTrue);
      expect(input.error.value, isNull);
    });
  });

  test('setInitial shows an existing position without reading anything', () {
    input.setInitial(const GeoPoint(33.5, 36.3));
    expect(input.point.value?.longitude, 36.3);
    expect(h.gps.reads, 0);
    input.setInitial(null);
    expect(input.point.value, isNull);
  });
}
