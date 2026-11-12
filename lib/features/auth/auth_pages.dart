import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../app/routes/page_factory.dart';
import 'auth_kind.dart';
import 'controllers/login_controller.dart';
import 'controllers/onboarding_controller.dart';
import 'controllers/password_reset_controller.dart';
import 'controllers/register_controller.dart';
import 'controllers/splash_controller.dart';
import 'controllers/verify_email_controller.dart';
import 'views/login_page.dart';
import 'views/legal_page.dart';
import 'views/onboarding_page.dart';
import 'views/password_reset_page.dart';
import 'views/register_page.dart';
import 'views/splash_page.dart';
import 'views/status_pages.dart';
import 'views/verify_email_page.dart';
import 'views/welcome_page.dart';

GetPage<dynamic> _login(String route, AuthKind kind) => appPage(
      route,
      () => LoginPage(kind),
      binding: BindingsBuilder<dynamic>(() => Get.lazyPut<LoginController>(() => LoginController(kind), tag: kind.name)),
    );

GetPage<dynamic> _register(String route, AuthKind kind) => appPage(
      route,
      () => RegisterPage(kind),
      binding: BindingsBuilder<dynamic>(() => Get.lazyPut<RegisterController>(() => RegisterController(kind), tag: kind.name)),
    );

/// Splash, onboarding, welcome, the three logins, registration, password reset, status and legal screens.
List<GetPage<dynamic>> authPages() => <GetPage<dynamic>>[
      appPage(
        AppRoutes.splash,
        () => const SplashPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<SplashController>(() => SplashController())),
      ),
      appPage(
        AppRoutes.onboarding,
        () => const OnboardingPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<OnboardingController>(() => OnboardingController())),
      ),
      appPage(AppRoutes.welcome, () => const WelcomePage()),
      _login(AppRoutes.login, AuthKind.customer),
      _login(AppRoutes.pharmacistLogin, AuthKind.pharmacist),
      _login(AppRoutes.adminLogin, AuthKind.admin),
      _register(AppRoutes.register, AuthKind.customer),
      _register(AppRoutes.pharmacistRegister, AuthKind.pharmacist),
      appPage(
        AppRoutes.passwordReset,
        () => const PasswordResetPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<PasswordResetController>(() => PasswordResetController())),
      ),
      appPage(
        AppRoutes.verifyEmail,
        () => const VerifyEmailPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<VerifyEmailController>(() => VerifyEmailController())),
      ),
      appPage(AppRoutes.accountSuspended, () => const AccountSuspendedPage()),
      appPage(AppRoutes.accessDenied, () => const AccessDeniedPage()),
      appPage(AppRoutes.notFound, () => const NotFoundPage()),
      appPage(AppRoutes.legalPrivacy, () => const LegalPage(LegalDoc.privacy)),
      appPage(AppRoutes.legalTerms, () => const LegalPage(LegalDoc.terms)),
    ];
