import 'package:get/get.dart';

/// Money, date and number formatting.
///
/// Digits are shown as ASCII (0-9) in both languages: this is what Syrian price tags, receipts and
/// pharmacy software use, and it keeps copy/paste and phone numbers unambiguous.
class Fmt {
  const Fmt._();

  /// `12500` + `SYP` → "12,500 ل.س" (ar) / "12,500 SYP" (en);  `12.5` + `USD` → "$12.50".
  static String money(num amount, String currency) {
    final bool isUsd = currency.toUpperCase() == 'USD';
    final num value = _round2(amount);
    final String body = isUsd ? _grouped(value, 2) : _grouped(value, _isWhole(value) ? 0 : 2);
    if (isUsd) return '\$$body';
    final String unit = Get.locale?.languageCode == 'en' ? 'SYP' : 'ل.س';
    return '$body $unit';
  }

  /// Plain number with thousands separators and at most [decimals] decimals (no trailing zeros).
  static String number(num value, {int decimals = 0}) {
    String s = _grouped(value, decimals);
    if (decimals > 0 && s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// `2026-10-12 21:14` in the device's local time.
  static String dateTime(DateTime? value) {
    if (value == null) return '—';
    final DateTime d = value.toLocal();
    return '${date(d)} ${_two(d.hour)}:${_two(d.minute)}';
  }

  static String date(DateTime? value) {
    if (value == null) return '—';
    final DateTime d = value.toLocal();
    return '${d.year}-${_two(d.month)}-${_two(d.day)}';
  }

  static String time(DateTime? value) {
    if (value == null) return '—';
    final DateTime d = value.toLocal();
    return '${_two(d.hour)}:${_two(d.minute)}';
  }

  /// Distance for a pharmacy card: "250 م" below one kilometre (rounded to 10 m), "1.3 كم" above. Empty when unknown.
  static String distance(double? km) {
    if (km == null || km.isNaN || km < 0) return '';
    if (km < 1) {
      final int m = ((km * 1000) / 10).round() * 10;
      // 995 m and more would round to "1000 m": that is written as kilometres instead.
      if (m < 1000) return 'distance_m'.trParams(<String, String>{'n': '${m < 10 ? 10 : m}'});
    }
    return 'distance_km'.trParams(<String, String>{'n': number(km, decimals: 1)});
  }

  /// "3 days ago" style age of a timestamp (used for "confirmed 3 days ago").
  static String ago(DateTime? value, {DateTime? now}) {
    if (value == null) return '—';
    final Duration d = (now ?? DateTime.now()).difference(value);
    if (d.inMinutes < 1) return 'ago_now'.tr;
    if (d.inMinutes < 60) return 'ago_minutes'.trParams(<String, String>{'n': '${d.inMinutes}'});
    if (d.inHours < 24) return 'ago_hours'.trParams(<String, String>{'n': '${d.inHours}'});
    return 'ago_days'.trParams(<String, String>{'n': '${d.inDays}'});
  }

  /// "2 h 15 m" style remaining time, localized by the caller through [hoursUnit]/[minutesUnit].
  static String remaining(Duration d, {required String hoursUnit, required String minutesUnit}) {
    if (d.isNegative) return '0 $minutesUnit';
    final int h = d.inHours;
    final int m = d.inMinutes % 60;
    if (h == 0) return '$m $minutesUnit';
    return '$h $hoursUnit $m $minutesUnit';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static num _round2(num v) => (v * 100).round() / 100;

  static bool _isWhole(num v) => v == v.roundToDouble();

  static String _grouped(num value, int decimals) {
    final String fixed = value.abs().toStringAsFixed(decimals);
    final List<String> parts = fixed.split('.');
    final String intPart = parts[0];
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) b.write(',');
      b.write(intPart[i]);
    }
    final String sign = value < 0 ? '-' : '';
    return parts.length > 1 ? '$sign$b.${parts[1]}' : '$sign$b';
  }
}

/// Money arithmetic helper: sums of decimals are rounded to 2 places so totals never show 1000.0000001.
double roundMoney(num value) => (value * 100).round() / 100;
