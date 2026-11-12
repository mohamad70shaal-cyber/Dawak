/// Tolerant JSON readers used by every model. PostgREST returns numerics as JSON numbers (or strings for
/// very large values), timestamps as ISO-8601 strings and missing columns as `null`.
class J {
  const J._();

  static String str(Object? v, [String fallback = '']) => v == null ? fallback : v.toString();

  static String? strOrNull(Object? v) {
    if (v == null) return null;
    final String s = v.toString();
    return s.isEmpty ? null : s;
  }

  static int integer(Object? v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  static double number(Object? v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static double? numberOrNull(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static bool boolean(Object? v, [bool fallback = false]) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final String s = v.toString().toLowerCase();
    return s == 'true' || s == 't' || s == '1';
  }

  static DateTime? date(Object? v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static Map<String, dynamic> map(Object? v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> list(Object? v) {
    if (v is List) {
      return v.whereType<Map>().map((Map e) => Map<String, dynamic>.from(e)).toList();
    }
    return <Map<String, dynamic>>[];
  }
}
