import 'dart:ui';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app language (Arabic by default, English optional) and the first-run flag. Persisted locally.
class LocaleService extends GetxService {
  LocaleService(this._prefs);

  final SharedPreferences _prefs;

  static const String _kLocale = 'locale';
  static const String _kOnboarded = 'onboarding_done';

  static const Locale arabic = Locale('ar');
  static const Locale english = Locale('en');
  static const List<Locale> supported = <Locale>[arabic, english];

  late final Rx<Locale> locale = _load().obs;

  Locale _load() => _prefs.getString(_kLocale) == 'en' ? english : arabic;

  bool get isArabic => locale.value.languageCode == 'ar';

  bool get onboardingDone => _prefs.getBool(_kOnboarded) ?? false;

  Future<void> markOnboardingDone() => _prefs.setBool(_kOnboarded, true);

  Future<void> setLocale(Locale l) async {
    if (!supported.any((Locale s) => s.languageCode == l.languageCode)) return;
    locale.value = l;
    await _prefs.setString(_kLocale, l.languageCode);
    Get.updateLocale(l);
  }

  Future<void> toggle() => setLocale(isArabic ? english : arabic);
}
