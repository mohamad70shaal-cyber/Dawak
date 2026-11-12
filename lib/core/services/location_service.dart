import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../../data/models/geo.dart';
import '../errors/app_failure.dart';

/// Where positions come from. The real one wraps the device GPS; tests pass a fake.
abstract class LocationGateway {
  /// Asks for permission when needed and returns the current position, or throws an [AppFailure] with one of
  /// `location_off`, `location_denied`, `location_denied_forever`, `location_timeout`, `location_unavailable`.
  Future<GeoPoint> currentPosition();

  /// Opens the system page where the user can grant the permission / switch location on.
  Future<void> openSettings();
}

class GeolocatorGateway implements LocationGateway {
  const GeolocatorGateway();

  @override
  Future<GeoPoint> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw const AppFailure('location_off');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw const AppFailure('location_denied');
      if (permission == LocationPermission.deniedForever) throw const AppFailure('location_denied_forever');
      final Position p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      final GeoPoint? g = GeoPoint.tryCreate(p.latitude, p.longitude);
      if (g == null) throw const AppFailure('location_unavailable');
      return g;
    } on TimeoutException {
      throw const AppFailure('location_timeout');
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure('location_unavailable');
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {
      // Ignore failures to open settings.
    }
  }
}

/// The device position for the customer's search and requests and for the pharmacist's shop location.
/// A position is remembered for [freshFor] so moving between screens does not re-ask the GPS every time.
class LocationService extends GetxService {
  LocationService(this._gateway, {this.freshFor = const Duration(minutes: 5), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final LocationGateway _gateway;
  final Duration freshFor;
  final DateTime Function() _clock;

  /// The last position that was read (null until the first success). Screens may show it as "your location".
  final Rxn<GeoPoint> lastKnown = Rxn<GeoPoint>();
  DateTime? _at;

  /// [forceFresh] skips the remembered position. Throws [AppFailure] (see [LocationGateway.currentPosition]).
  Future<GeoPoint> locate({bool forceFresh = false}) async {
    final GeoPoint? known = lastKnown.value;
    final DateTime? at = _at;
    if (!forceFresh && known != null && at != null && _clock().difference(at) < freshFor) return known;
    final GeoPoint p = await _gateway.currentPosition();
    lastKnown.value = p;
    _at = _clock();
    return p;
  }

  /// Forget the remembered position (sign-out).
  void forget() {
    lastKnown.value = null;
    _at = null;
  }

  Future<void> openSettings() => _gateway.openSettings();
}
