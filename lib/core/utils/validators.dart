import 'package:get/get.dart';

import 'phone_utils.dart';

/// Form validators. Each returns a localized message (via the translation table) or null when valid.
/// Server-side validation is authoritative; these only give instant feedback.
class Validators {
  const Validators._();

  static String? required(String? v, {String? fieldKey}) {
    if (v == null || v.trim().isEmpty) return 'val_required'.tr;
    return null;
  }

  static String? email(String? v) {
    final String s = (v ?? '').trim();
    if (s.isEmpty) return 'val_required'.tr;
    if (s.length > 254 || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(s)) return 'val_email'.tr;
    return null;
  }

  static String? password(String? v) {
    final String s = v ?? '';
    if (s.isEmpty) return 'val_required'.tr;
    if (s.length < 8) return 'val_password_short'.tr;
    if (s.length > 72) return 'val_password_long'.tr;
    return null;
  }

  static String? Function(String?) confirmPassword(String Function() original) {
    return (String? v) {
      if ((v ?? '').isEmpty) return 'val_required'.tr;
      if (v != original()) return 'val_password_mismatch'.tr;
      return null;
    };
  }

  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return 'val_required'.tr;
    return cleanPhone(v) == null ? 'val_phone'.tr : null;
  }

  static String? optionalPhone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return cleanPhone(v) == null ? 'val_phone'.tr : null;
  }

  static String? Function(String?) length({int min = 0, required int max}) {
    return (String? v) {
      final String s = (v ?? '').trim();
      if (min > 0 && s.length < min) return min == 1 ? 'val_required'.tr : 'val_too_short'.trParams(<String, String>{'n': '$min'});
      if (s.length > max) return 'val_too_long'.trParams(<String, String>{'n': '$max'});
      return null;
    };
  }

  /// A price with at most two decimals. Accepts Arabic-Indic digits and a comma/Arabic decimal separator.
  static String? price(String? v, {bool allowZero = true}) {
    final double? d = parseDecimal(v);
    if (d == null) return 'val_number'.tr;
    if (d < 0 || (!allowZero && d == 0)) return 'val_amount_positive'.tr;
    if (d > 999999999999) return 'val_too_large'.tr;
    final String s = normalizeDigits(v!).replaceAll(',', '.').replaceAll('٫', '.');
    final int dot = s.indexOf('.');
    if (dot >= 0 && s.length - dot - 1 > 2) return 'val_max_two_decimals'.tr;
    return null;
  }

  static String? Function(String?) integer({int min = 0, int max = 1000000}) {
    return (String? v) {
      final int? n = parseInt(v);
      if (n == null) return 'val_integer'.tr;
      if (n < min) return 'val_min_value'.trParams(<String, String>{'n': '$min'});
      if (n > max) return 'val_max_value'.trParams(<String, String>{'n': '$max'});
      return null;
    };
  }

  static String normalizeDigits(String input) {
    final StringBuffer b = StringBuffer();
    for (final int r in input.trim().runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(0x30 + (r - 0x0660));
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(0x30 + (r - 0x06F0));
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  static double? parseDecimal(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final String s = normalizeDigits(v).replaceAll(',', '.').replaceAll('٫', '.');
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;
    return double.tryParse(s);
  }

  static int? parseInt(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final String s = normalizeDigits(v);
    if (!RegExp(r'^\d+$').hasMatch(s)) return null;
    return int.tryParse(s);
  }
}
