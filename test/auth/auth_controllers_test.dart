import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/base/base_controller.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/core/services/locale_service.dart';
import 'package:dawak/features/auth/auth_kind.dart';
import 'package:dawak/features/auth/controllers/login_controller.dart';
import 'package:dawak/features/auth/controllers/password_reset_controller.dart';
import 'package:dawak/features/auth/controllers/register_controller.dart';
import 'package:dawak/features/auth/controllers/splash_controller.dart';
import 'package:dawak/features/auth/controllers/verify_email_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';

/// Controllers read their form through a `GlobalKey<FormState>`; unit tests have no widget tree, so the
/// forms are validated by the field validators in widget tests and here we exercise the controller's logic
/// through a tiny host that mounts the form.
Future<void> mountForm(WidgetTester tester, GlobalKey<FormState> key) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: key, child: const SizedBox()))));
}

void main() {
  late AppHarness h;
  late List<String> offAll;
  setUp(() async {
    h = await AppHarness.create();
    offAll = <String>[];
  });
  tearDown(() => h.dispose());

  void navigate(String route, {Object? arguments}) => offAll.add(route);

  group('LoginController', () {
    LoginController make(AuthKind k) => LoginController(k, offAll: navigate)..onInit();

    testWidgets('customer signs in and lands on the customer home', (WidgetTester tester) async {
      h.auth.addUser('c@test.dev', 'password1', id: 'c1');
      h.api.tables['profiles'] = <Map<String, dynamic>>[Fx.profileRow('c1')];
      final LoginController c = make(AuthKind.customer);
      await mountForm(tester, c.form);
      c.email.text = 'c@test.dev';
      c.password.text = 'password1';
      await c.signIn();
      expect(offAll, <String>[AppRoutes.customerHome]);
      expect(c.password.text, isEmpty, reason: 'password is not kept after success');
    });

    testWidgets('wrong password shows the localized error and stays put', (WidgetTester tester) async {
      h.auth.addUser('c@test.dev', 'password1', id: 'c1');
      final LoginController c = make(AuthKind.customer);
      await mountForm(tester, c.form);
      c.email.text = 'c@test.dev';
      c.password.text = 'nope-nope';
      await c.signIn();
      expect(offAll, isEmpty);
      expect(c.failure.value?.code, 'invalid_credentials');
      expect(failureText(c.failure.value!), 'err_invalid_credentials'.tr);
      expect(c.submitting.value, isFalse);
    });

    testWidgets('a pharmacist account at the customer door is signed out again with an explanation', (WidgetTester tester) async {
      h.auth.addUser('p@test.dev', 'password1', id: 'p1');
      h.api.tables['profiles'] = <Map<String, dynamic>>[Fx.profileRow('p1', role: 'pharmacist')];
      h.api.tables['pharmacies'] = <Map<String, dynamic>>[Fx.pharmacyRow('ph1', owner: 'p1')];
      h.api.tables['pharmacy_members'] = <Map<String, dynamic>>[Fx.memberRow('ph1', 'p1')];
      final LoginController c = make(AuthKind.customer);
      await mountForm(tester, c.form);
      c.email.text = 'p@test.dev';
      c.password.text = 'password1';
      await c.signIn();
      expect(offAll, isEmpty);
      expect(h.auth.hasSession, isFalse, reason: 'session discarded');
      expect(h.session.signedIn, isFalse);
      expect(c.notice.value, 'auth_wrong_role_customer'.tr);
    });

    testWidgets('a customer account at the admin door is rejected', (WidgetTester tester) async {
      h.auth.addUser('c@test.dev', 'password1', id: 'c1');
      h.api.tables['profiles'] = <Map<String, dynamic>>[Fx.profileRow('c1')];
      final LoginController c = make(AuthKind.admin);
      await mountForm(tester, c.form);
      c.email.text = 'c@test.dev';
      c.password.text = 'password1';
      await c.signIn();
      expect(offAll, isEmpty);
      expect(c.notice.value, 'auth_wrong_role_admin'.tr);
    });

    testWidgets('approved pharmacist lands on the dashboard; applicant (customer role) goes to the wizard', (WidgetTester tester) async {
      h.auth.addUser('p@test.dev', 'password1', id: 'p1');
      h.auth.addUser('a@test.dev', 'password1', id: 'a1');
      h.api.tables['profiles'] = <Map<String, dynamic>>[Fx.profileRow('p1', role: 'pharmacist'), Fx.profileRow('a1')];
      h.api.tables['pharmacies'] = <Map<String, dynamic>>[Fx.pharmacyRow('ph1', owner: 'p1')];
      h.api.tables['pharmacy_members'] = <Map<String, dynamic>>[Fx.memberRow('ph1', 'p1')];

      final LoginController c = make(AuthKind.pharmacist);
      await mountForm(tester, c.form);
      c.email.text = 'p@test.dev';
      c.password.text = 'password1';
      await c.signIn();
      expect(offAll.last, AppRoutes.pharmacistDashboard);

      await h.session.signOut();
      c.email.text = 'a@test.dev';
      c.password.text = 'password1';
      await c.signIn();
      expect(offAll.last, AppRoutes.pharmacyRegister);
    });

    testWidgets('a suspended account is routed to the suspended screen, not rejected', (WidgetTester tester) async {
      h.auth.addUser('c@test.dev', 'password1', id: 'c1');
      h.api.tables['profiles'] = <Map<String, dynamic>>[Fx.profileRow('c1', status: 'suspended')];
      final LoginController c = make(AuthKind.customer);
      await mountForm(tester, c.form);
      c.email.text = 'c@test.dev';
      c.password.text = 'password1';
      await c.signIn();
      expect(offAll.last, AppRoutes.accountSuspended);
    });

    testWidgets('unconfirmed e-mail offers to resend the confirmation', (WidgetTester tester) async {
      final LoginController c = make(AuthKind.customer);
      await mountForm(tester, c.form);
      c.email.text = 'c@test.dev';
      c.password.text = 'password1';
      h.auth.nextFailure = const AppFailure('email_not_confirmed');
      await c.signIn();
      expect(c.needsConfirmation, isTrue);
      await c.resendConfirmation();
      expect(h.auth.resendRequests, <String>['c@test.dev']);
    });

    testWidgets('invalid form never reaches the network', (WidgetTester tester) async {
      final LoginController c = make(AuthKind.customer);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: c.form,
            child: TextFormField(controller: c.email, validator: (String? v) => (v ?? '').isEmpty ? 'required' : null),
          ),
        ),
      ));
      await c.signIn();
      expect(h.auth.hasSession, isFalse);
      expect(h.api.calls, isEmpty);
    });
  });

  group('RegisterController', () {
    RegisterController make(AuthKind k) => RegisterController(k, offAll: navigate)..onInit();

    Future<void> fill(RegisterController c) async {
      c.name.text = 'Mohamad';
      c.email.text = 'new@test.dev';
      c.password.text = 'password1';
      c.confirm.text = 'password1';
    }

    testWidgets('requires accepting the terms', (WidgetTester tester) async {
      final RegisterController c = make(AuthKind.customer);
      await mountForm(tester, c.form);
      await fill(c);
      await c.register();
      expect(c.termsError.value, isTrue);
      expect(h.auth.users, isEmpty);
    });

    testWidgets('with confirmation required: goes to verify-email carrying the address and door', (WidgetTester tester) async {
      final List<Object?> args = <Object?>[];
      final RegisterController c = RegisterController(AuthKind.pharmacist, offAll: (String r, {Object? arguments}) {
        offAll.add(r);
        args.add(arguments);
      })..onInit();
      await mountForm(tester, c.form);
      await fill(c);
      c.acceptedTerms.value = true;
      await c.register();
      expect(offAll, <String>[AppRoutes.verifyEmail]);
      expect(args.single, <String, String>{'email': 'new@test.dev', 'kind': 'pharmacist'});
      expect(h.auth.hasSession, isFalse);
    });

    testWidgets('with confirmation off: pharmacist continues into the wizard, customer to home', (WidgetTester tester) async {
      h.auth.confirmationsOff = true;
      h.api.tables['profiles'] = <Map<String, dynamic>>[Fx.profileRow('user-1')];

      final RegisterController pharm = make(AuthKind.pharmacist);
      await mountForm(tester, pharm.form);
      await fill(pharm);
      pharm.acceptedTerms.value = true;
      await pharm.register();
      expect(offAll.last, AppRoutes.pharmacyRegister);

      await h.session.signOut();
      final RegisterController cust = make(AuthKind.customer);
      await mountForm(tester, cust.form);
      cust.name.text = 'Other';
      cust.email.text = 'other@test.dev';
      cust.password.text = 'password1';
      cust.confirm.text = 'password1';
      cust.acceptedTerms.value = true;
      h.api.tables['profiles']!.add(Fx.profileRow('user-2'));
      await cust.register();
      expect(offAll.last, AppRoutes.customerHome);
    });

    testWidgets('an already-registered e-mail shows the localized error', (WidgetTester tester) async {
      h.auth.addUser('new@test.dev', 'password1');
      final RegisterController c = make(AuthKind.customer);
      await mountForm(tester, c.form);
      await fill(c);
      c.acceptedTerms.value = true;
      await c.register();
      expect(c.failure.value?.code, 'email_taken');
      expect(offAll, isEmpty);
    });

    test('admin accounts cannot be self-registered', () {
      expect(() => RegisterController(AuthKind.admin), throwsAssertionError);
    });
  });

  group('PasswordResetController', () {
    testWidgets('sends the request and shows the neutral confirmation', (WidgetTester tester) async {
      final PasswordResetController c = PasswordResetController()..onInit();
      await mountForm(tester, c.form);
      c.email.text = 'someone@test.dev';
      await c.send();
      expect(c.sent.value, isTrue);
      expect(h.auth.resetRequests, <String>['someone@test.dev']);
    });
  });

  group('VerifyEmailController', () {
    test('reads address and door from arguments', () {
      final VerifyEmailController c = VerifyEmailController(arguments: <String, dynamic>{'email': 'a@b.co', 'kind': 'pharmacist'});
      expect(c.email, 'a@b.co');
      expect(c.kind, AuthKind.pharmacist);
    });
    test('defaults to the customer door', () {
      expect(VerifyEmailController(arguments: <String, dynamic>{}).kind, AuthKind.customer);
    });
    test('resend uses the address', () async {
      final VerifyEmailController c = VerifyEmailController(arguments: <String, dynamic>{'email': 'a@b.co'});
      await c.resend();
      expect(h.auth.resendRequests, <String>['a@b.co']);
    });
  });

  group('SplashController', () {
    SplashController make() => SplashController(offAll: navigate, minimumShow: Duration.zero);

    test('first run without a session: onboarding', () async {
      await make().start();
      expect(offAll, <String>[AppRoutes.onboarding]);
    });

    test('returning user without a session: welcome', () async {
      await Get.find<LocaleService>().markOnboardingDone();
      await make().start();
      expect(offAll, <String>[AppRoutes.welcome]);
    });

    test('valid session: straight to the role home', () async {
      h.signInAs('u1', role: 'pharmacist', pharmacy: Fx.pharmacyRow('ph1', owner: 'u1', status: 'pending'));
      await make().start();
      expect(offAll, <String>[AppRoutes.statusPending]);
    });

    test('network failure shows an error state and allows retry', () async {
      h.signInAs('c1');
      h.api.failNext('select:profiles', const AppFailure('network'));
      final SplashController c = make();
      await c.start();
      expect(c.status.value, ViewStatus.error);
      expect(offAll, isEmpty);
      await c.start();
      expect(offAll, <String>[AppRoutes.customerHome]);
    });

    test('an invalid stored session is dropped and the user starts clean', () async {
      h.signInAs('c1');
      h.api.failNext('select:profiles', const AppFailure('not_authenticated'));
      await make().start();
      expect(h.auth.hasSession, isFalse);
      expect(offAll, <String>[AppRoutes.onboarding]);
    });
  });
}
