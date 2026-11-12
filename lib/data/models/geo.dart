import 'dart:math' as math;

import 'json_utils.dart';

/// A position on the map. Pharmacies publish theirs; a customer's is only ever sent to the server (rounded there).
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Same rule as `private.check_location`: finite, in range and not the "no fix" value (0, 0).
  static bool isValid(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return false;
    if (latitude.isNaN || longitude.isNaN || latitude.isInfinite || longitude.isInfinite) return false;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return false;
    return !(latitude == 0 && longitude == 0);
  }

  /// Null when either value is missing or the pair is not a usable position.
  static GeoPoint? tryCreate(Object? latitude, Object? longitude) {
    final double? lat = J.numberOrNull(latitude);
    final double? lng = J.numberOrNull(longitude);
    return isValid(lat, lng) ? GeoPoint(lat!, lng!) : null;
  }

  /// Great-circle distance in kilometres (haversine, mean earth radius 6371 km, as in `private.distance_km`).
  double distanceKmTo(GeoPoint other) {
    const double r = 6371.0;
    final double dLat = _rad(other.latitude - latitude);
    final double dLon = _rad(other.longitude - longitude);
    final double a = math.pow(math.sin(dLat / 2), 2).toDouble() +
        math.cos(_rad(latitude)) * math.cos(_rad(other.latitude)) * math.pow(math.sin(dLon / 2), 2).toDouble();
    return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  /// "33.51020, 36.27650" (always with a dot, whatever the app language).
  String get label => '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  @override
  bool operator ==(Object other) => other is GeoPoint && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($label)';
}
