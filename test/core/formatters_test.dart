// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'dart:ui';

import 'package:dawak/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/harness.dart';

void main() {
  late AppHarness h;
  setUp(() async => h = await AppHarness.create());
  tearDown(() => h.dispose());

  group('money', () {
    test('Syrian pounds: grouped, no decimals when whole, two when not', () {
      expect(Fmt.money(12500, 'SYP'), '12,500 SYP');
      expect(Fmt.money(12.5, 'SYP'), '12.50 SYP');
      expect(Fmt.money(1250000, 'SYP'), '1,250,000 SYP');
      expect(Fmt.money(0, 'SYP'), '0 SYP');
    });

    test('dollars always show two decimals', () {
      expect(Fmt.money(12.5, 'USD'), '\$12.50');
      expect(Fmt.money(1200, 'usd'), '\$1,200.00');
    });

    test('the unit follows the app language', () {
      Get.locale = const Locale('ar');
      expect(Fmt.money(12500, 'SYP'), '12,500 ل.س');
    });

    test('floating point dust is rounded away', () {
      expect(Fmt.money(0.1 + 0.2, 'SYP'), '0.30 SYP');
      expect(Fmt.money(1000.004, 'SYP'), '1,000 SYP');
      expect(roundMoney(1250.5 * 3), 3751.5);
    });

    test('negative amounts keep their sign', () {
      expect(Fmt.money(-5000, 'SYP'), '-5,000 SYP');
    });
  });

  group('number', () {
    test('thousands separators and trimmed decimals', () {
      expect(Fmt.number(1234567), '1,234,567');
      expect(Fmt.number(10), '10');
      expect(Fmt.number(1.5, decimals: 1), '1.5');
      expect(Fmt.number(2.0, decimals: 1), '2');
      expect(Fmt.number(0.0, decimals: 2), '0');
      expect(Fmt.number(3, decimals: 1), '3');
    });
  });

  group('distance', () {
    test('unknown or impossible distances show nothing', () {
      expect(Fmt.distance(null), '');
      expect(Fmt.distance(double.nan), '');
      expect(Fmt.distance(-1), '');
    });

    test('below a kilometre: metres rounded to 10, never less than 10', () {
      expect(Fmt.distance(0.25), '250 m');
      expect(Fmt.distance(0.254), '250 m');
      expect(Fmt.distance(0.004), '10 m');
      expect(Fmt.distance(0.0), '10 m');
    });

    test('from a kilometre: one decimal at most, no trailing zero', () {
      expect(Fmt.distance(1), '1 km');
      expect(Fmt.distance(1.26), '1.3 km');
      expect(Fmt.distance(12.04), '12 km');
    });

    test('995 m and above is written in kilometres, never as "1000 m"', () {
      expect(Fmt.distance(0.999), '1 km');
      expect(Fmt.distance(0.996), '1 km');
      expect(Fmt.distance(0.994), '990 m');
    });
  });

  group('ago', () {
    final DateTime t = DateTime(2026, 10, 10, 12);

    test('an unknown time is a dash', () {
      expect(Fmt.ago(null), '—');
    });

    test('the unit steps: now, minutes, hours, days', () {
      expect(Fmt.ago(t, now: t.add(const Duration(seconds: 30))), 'Just now');
      expect(Fmt.ago(t, now: t.add(const Duration(minutes: 5))), '5 min ago');
      expect(Fmt.ago(t, now: t.add(const Duration(minutes: 59))), '59 min ago');
      expect(Fmt.ago(t, now: t.add(const Duration(minutes: 60))), '1 h ago');
      expect(Fmt.ago(t, now: t.add(const Duration(hours: 23, minutes: 59))), '23 h ago');
      expect(Fmt.ago(t, now: t.add(const Duration(hours: 24))), '1 d ago');
      expect(Fmt.ago(t, now: t.add(const Duration(days: 9))), '9 d ago');
    });

    test('a time slightly in the future (clock difference with the server) reads as "just now"', () {
      expect(Fmt.ago(t.add(const Duration(minutes: 2)), now: t), 'Just now');
    });
  });

  group('remaining', () {
    test('hours and minutes, minutes alone, never negative', () {
      expect(Fmt.remaining(const Duration(hours: 2, minutes: 15), hoursUnit: 'h', minutesUnit: 'm'), '2 h 15 m');
      expect(Fmt.remaining(const Duration(minutes: 45), hoursUnit: 'h', minutesUnit: 'm'), '45 m');
      expect(Fmt.remaining(Duration.zero, hoursUnit: 'h', minutesUnit: 'm'), '0 m');
      expect(Fmt.remaining(const Duration(minutes: -3), hoursUnit: 'h', minutesUnit: 'm'), '0 m');
    });
  });
}
