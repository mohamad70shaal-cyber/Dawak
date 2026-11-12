import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/app/routes/session_snapshot.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/datasources/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';

void main() {
  late AppHarness h;
  setUp(() async => h = await AppHarness.create());
  tearDown(() => h.dispose());

  test('restore without a session yields signed-out', () async {
    final SessionSnapshot s = await h.session.restore();
    expect(s.signedIn, isFalse);
    expect(h.session.homeRoute, AppRoutes.welcome);
  });

  test('restore loads profile and, for pharmacists, the pharmacy with the member role', () async {
    h.signInAs('u1', role: 'pharmacist', pharmacy: Fx.pharmacyRow('ph1', owner: 'u1'), memberRole: 'manager');
    final SessionSnapshot s = await h.session.restore();
    expect(s.signedIn, isTrue);
    expect(s.pharmacy?.id, 'ph1');
    expect(s.memberRole?.name, 'manager');
    expect(h.session.homeRoute, AppRoutes.pharmacistDashboard);
  });

  test('customers never trigger a pharmacy query', () async {
    h.signInAs('c1');
    await h.session.restore();
    expect(h.api.calls.where((String c) => c == 'select:pharmacies'), isEmpty);
    expect(h.session.homeRoute, AppRoutes.customerHome);
  });

  test('a suspended profile routes to the suspended screen', () async {
    h.signInAs('c1', status: 'suspended');
    await h.session.restore();
    expect(h.session.homeRoute, AppRoutes.accountSuspended);
  });

  test('signOut clears state and navigates to welcome', () async {
    h.signInAs('c1');
    await h.session.restore();
    await h.session.signOut();
    expect(h.session.signedIn, isFalse);
    expect(h.navigated.last, AppRoutes.welcome);
  });

  test('an unexpected sign-out event marks the session as expired and goes to welcome', () async {
    h.signInAs('c1');
    await h.session.restore();
    h.auth.emit(AuthEventKind.signedOut);
    await Future<void>.delayed(Duration.zero);
    expect(h.session.signedIn, isFalse);
    expect(h.session.sessionExpired.value, isTrue);
    expect(h.navigated.last, AppRoutes.welcome);
  });

  test('refresh navigates when the pharmacy gets approved', () async {
    h.signInAs('u1', role: 'pharmacist', pharmacy: Fx.pharmacyRow('ph1', owner: 'u1', status: 'pending'));
    await h.session.restore();
    expect(h.session.homeRoute, AppRoutes.statusPending);
    h.api.tables['pharmacies']!.first['approval_status'] = 'approved';
    await h.session.refresh();
    expect(h.navigated.last, AppRoutes.pharmacistDashboard);
  });

  test('refresh with a lost connection keeps the state and does not navigate', () async {
    h.signInAs('c1');
    await h.session.restore();
    h.api.failNext('select:profiles', const AppFailure('network'));
    await h.session.refresh();
    expect(h.session.signedIn, isTrue);
    expect(h.navigated, isEmpty);
  });

  test('handleFailure(account_suspended) refreshes and navigates to the suspended screen', () async {
    h.signInAs('c1');
    await h.session.restore();
    h.api.tables['profiles']!.first['account_status'] = 'suspended';
    await h.session.handleFailure(const AppFailure('account_suspended'));
    expect(h.navigated.last, AppRoutes.accountSuspended);
  });

  test('a blocked deep link is resumed after login when the role may open it', () async {
    h.session.rememberBlockedTarget('/customer/orders/42');
    h.signInAs('c1');
    await h.session.restore();
    expect(h.session.routeAfterLogin(), '/customer/orders/42');
    // consumed: asking again gives the role home
    expect(h.session.routeAfterLogin(), AppRoutes.customerHome);
  });

  test('a blocked deep link the role may not open is dropped in favour of the home route', () async {
    h.session.rememberBlockedTarget('/admin/users');
    h.signInAs('c1');
    await h.session.restore();
    expect(h.session.routeAfterLogin(), AppRoutes.customerHome);
  });

  test('public and guest-only routes are never remembered', () {
    h.session.rememberBlockedTarget(AppRoutes.login);
    h.session.rememberBlockedTarget(AppRoutes.legalTerms);
    expect(h.session.routeAfterLogin(), AppRoutes.welcome);
  });
}
