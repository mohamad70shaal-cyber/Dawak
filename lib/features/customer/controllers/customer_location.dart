import 'dart:async';

import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/location_service.dart';
import '../../../data/models/geo.dart';

/// Where the customer is, for the screens that sort by distance or start an "ask nearby" request. Wraps the shared
/// [LocationService] (which remembers a position for a few minutes) and keeps what a screen needs to explain a failure:
/// a translated message and whether only the phone's settings can fix it (location off, permission blocked).
///
/// Several callers may ask at once (the list loads while "ask nearby" is tapped): they share one GPS read.
class CustomerLocation {
  CustomerLocation({LocationService? service}) : _service = service ?? Get.find<LocationService>();

  final LocationService _service;

  /// The last position this screen obtained (null until a read succeeded).
  final Rxn<GeoPoint> point = Rxn<GeoPoint>();

  final RxBool locating = false.obs;

  /// Translated explanation of the last failure; null when the last read worked.
  final RxnString error = RxnString();

  /// True after a failure that only the system settings can fix.
  final RxBool needsSettings = false.obs;

  Future<GeoPoint?>? _inflight;

  /// The position, or null when it could not be read (then [error] says why). Never throws.
  Future<GeoPoint?> locate({bool forceFresh = false}) => _inflight ??= _read(forceFresh).whenComplete(() => _inflight = null);

  Future<GeoPoint?> _read(bool forceFresh) async {
    locating.value = true;
    error.value = null;
    needsSettings.value = false;
    try {
      final GeoPoint p = await _service.locate(forceFresh: forceFresh).timeout(const Duration(seconds: 15));
      point.value = p;
      return p;
    } on TimeoutException {
      const AppFailure f = AppFailure('location_timeout');
      error.value = failureText(f);
      needsSettings.value = false;
      return null;
    } catch (e) {
      final AppFailure f = AppFailure.from(e);
      error.value = failureText(f);
      needsSettings.value = f.code == 'location_off' || f.code == 'location_denied_forever';
      return null;
    } finally {
      locating.value = false;
    }
  }

  void clearError() {
    error.value = null;
    needsSettings.value = false;
  }

  Future<void> openSettings() => _service.openSettings();
}
