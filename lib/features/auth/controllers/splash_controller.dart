import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/shell_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/locale_service.dart';
import '../../../core/services/session_service.dart';

/// Start-up: restore the session (profile + pharmacy), then go to onboarding, the welcome screen or the role home.
class SplashController extends BaseController {
  SplashController({SessionService? session, LocaleService? locale, OffAll? offAll, this.minimumShow = const Duration(milliseconds: 1200)})
      : _session = session ?? Get.find<SessionService>(),
        _locale = locale ?? Get.find<LocaleService>(),
        _offAll = offAll ?? defaultOffAll;

  final SessionService _session;
  final LocaleService _locale;
  final OffAll _offAll;
  final Duration minimumShow;

  @override
  void onReady() {
    super.onReady();
    start();
  }

  Future<void> start() async {
    status.value = ViewStatus.loading;
    failure.value = null;
    final Future<void> pause = Future<void>.delayed(minimumShow);
    try {
      await _session.restore();
      await pause;
    } catch (e) {
      final AppFailure f = AppFailure.from(e);
      if (f.isSessionProblem) {
        // The stored session is no longer valid: start clean.
        await _session.discardSession();
        await pause;
        _offAll(_locale.onboardingDone ? AppRoutes.welcome : AppRoutes.onboarding);
        return;
      }
      failure.value = f;
      status.value = ViewStatus.error;
      return;
    }
    if (!_session.signedIn) {
      _offAll(_locale.onboardingDone ? AppRoutes.welcome : AppRoutes.onboarding);
    } else {
      _offAll(_session.homeRoute);
    }
  }

  /// From the error state: give up on the stored session and sign in again.
  Future<void> signOutAndRestart() async {
    await _session.discardSession();
    _offAll(AppRoutes.welcome);
  }
}
