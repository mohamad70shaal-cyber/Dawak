import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/location_service.dart';
import '../../../core/utils/geo_parse.dart';
import '../../../data/models/geo.dart';

/// The state behind the "shop location" card (registration address step and the settings screen): the chosen position,
/// reading it from the phone's GPS, or taking it from a pasted map link / coordinates. Shared by two controllers so both
/// screens behave the same.
class ShopLocationInput {
  ShopLocationInput({LocationService? location}) : _location = location ?? Get.find<LocationService>();

  final LocationService _location;

  /// The position that will be saved (null until one was chosen).
  final Rxn<GeoPoint> point = Rxn<GeoPoint>();

  /// The paste field (a map link or "33.5102, 36.2765").
  final TextEditingController paste = TextEditingController();

  /// True while the GPS is being read.
  final RxBool locating = false.obs;

  /// Translated message under the card (GPS failure, unreadable paste); null when everything is fine.
  final RxnString error = RxnString();

  /// True after a GPS failure that only the system settings can fix (location switched off, permission blocked).
  final RxBool needsSettings = false.obs;

  void dispose() => paste.dispose();

  void setInitial(GeoPoint? p) => point.value = p;

  /// "Use my current location": asks for permission when needed. Returns true when a position was read.
  Future<bool> useCurrent() async {
    if (locating.value) return false;
    locating.value = true;
    error.value = null;
    needsSettings.value = false;
    try {
      point.value = await _location.locate(forceFresh: true);
      paste.clear();
      return true;
    } catch (e) {
      final AppFailure f = AppFailure.from(e);
      error.value = failureText(f);
      needsSettings.value = f.code == 'location_off' || f.code == 'location_denied_forever';
      return false;
    } finally {
      locating.value = false;
    }
  }

  /// Takes the position from the paste field. Returns false (and says why) when nothing usable was found.
  bool usePasted() {
    error.value = null;
    needsSettings.value = false;
    final String text = paste.text;
    final GeoPoint? p = GeoParse.parse(text);
    if (p == null) {
      error.value = (GeoParse.isShortLink(text) ? 'p_loc_short_link' : 'p_loc_paste_invalid').tr;
      return false;
    }
    point.value = p;
    return true;
  }

  Future<void> openSettings() => _location.openSettings();
}
