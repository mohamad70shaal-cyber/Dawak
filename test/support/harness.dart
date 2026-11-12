import 'dart:ui';

import 'package:dawak/app/bindings/dependencies.dart';
import 'package:dawak/core/i18n/app_translations.dart';
import 'package:dawak/core/services/session_service.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api.dart';

/// Everything a controller test needs: fakes registered the same way `main.dart` registers the real ones,
/// translations loaded (so `'key'.tr` returns text) and a recorder for navigation.
class AppHarness {
  AppHarness._(this.api, this.auth, this.files, this.navigated, this.gps);

  final FakeApiClient api;
  final FakeAuthGateway auth;
  final FakeFileStore files;

  /// The scripted GPS behind `LocationService` (change `position` / `failure` between steps).
  final FakeLocationGateway gps;

  /// Routes passed to the session's navigate callback, in order.
  final List<String> navigated;

  SessionService get session => Get.find<SessionService>();

  /// Call from `setUp`. [locale] is `'ar'` or `'en'`; assert on English text only when it is the key's meaning
  /// that matters, otherwise compare against `key.tr`.
  static Future<AppHarness> create({String locale = 'en', Duration pollInterval = const Duration(hours: 1)}) async {
    Get.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final FakeApiClient api = FakeApiClient();
    final FakeAuthGateway auth = FakeAuthGateway();
    final FakeFileStore files = FakeFileStore();
    final FakeLocationGateway gps = FakeLocationGateway();
    final List<String> navigated = <String>[];
    registerCoreDependencies(
      api: api,
      auth: auth,
      files: files,
      location: gps,
      prefs: prefs,
      navigate: navigated.add,
      pollInterval: pollInterval,
    );
    Get.addTranslations(AppTranslations().keys);
    Get.locale = Locale(locale);
    Get.fallbackLocale = const Locale('ar');
    return AppHarness._(api, auth, files, navigated, gps);
  }

  /// Seeds an account and opens a session for it (profile row, optional pharmacy + membership).
  void signInAs(String userId, {String role = 'customer', String status = 'active', Map<String, dynamic>? pharmacy, String memberRole = 'owner'}) {
    auth.startSession(userId, '$userId@test.dev');
    (api.tables['profiles'] ??= <Map<String, dynamic>>[]).add(<String, dynamic>{
      'id': userId,
      'role': role,
      'account_status': status,
      'display_name': 'Test $userId',
      'phone': null,
      'locale': 'ar',
      'suspended_reason': status == 'suspended' ? 'test reason' : null,
      'created_at': '2026-10-01T10:00:00Z',
    });
    if (pharmacy != null) {
      (api.tables['pharmacies'] ??= <Map<String, dynamic>>[]).add(pharmacy);
      (api.tables['pharmacy_members'] ??= <Map<String, dynamic>>[]).add(<String, dynamic>{
        'pharmacy_id': pharmacy['id'],
        'user_id': userId,
        'role': memberRole,
        'status': 'active',
      });
    }
  }

  void dispose() => Get.reset();
}
