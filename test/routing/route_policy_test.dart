import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/app/routes/route_policy.dart';
import 'package:dawak/app/routes/session_snapshot.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

SessionSnapshot snap({UserRole? role, bool suspended = false, ApprovalStatus? pharmacy, MemberRole member = MemberRole.owner, bool profile = true}) {
  if (role == null) return SessionSnapshot.signedOut;
  return SessionSnapshot(
    signedIn: true,
    profile: profile ? Fx.profile(role: role, suspended: suspended) : null,
    pharmacy: pharmacy == null ? null : Fx.pharmacy(status: pharmacy, role: member),
  );
}

void main() {
  final SessionSnapshot out = snap();
  final SessionSnapshot customer = snap(role: UserRole.customer);
  final SessionSnapshot admin = snap(role: UserRole.admin);
  final SessionSnapshot approved = snap(role: UserRole.pharmacist, pharmacy: ApprovalStatus.approved);
  final SessionSnapshot cashier = snap(role: UserRole.pharmacist, pharmacy: ApprovalStatus.approved, member: MemberRole.cashier);
  final SessionSnapshot pending = snap(role: UserRole.pharmacist, pharmacy: ApprovalStatus.pending);
  final SessionSnapshot rejected = snap(role: UserRole.pharmacist, pharmacy: ApprovalStatus.rejected);
  final SessionSnapshot suspendedPharmacy = snap(role: UserRole.pharmacist, pharmacy: ApprovalStatus.suspended);
  final SessionSnapshot noPharmacy = snap(role: UserRole.pharmacist);

  String? go(String r, SessionSnapshot s) => RoutePolicy.redirectFor(r, s);

  group('public routes', () {
    for (final String r in <String>[AppRoutes.splash, AppRoutes.onboarding, AppRoutes.notFound, AppRoutes.accessDenied, AppRoutes.legalPrivacy, AppRoutes.legalTerms, AppRoutes.accountSuspended]) {
      test('$r open for everyone', () {
        for (final SessionSnapshot s in <SessionSnapshot>[out, customer, admin, approved]) {
          expect(go(r, s), isNull);
        }
      });
    }
  });

  group('guest-only routes', () {
    final List<String> routes = <String>[AppRoutes.welcome, AppRoutes.login, AppRoutes.register, AppRoutes.passwordReset, AppRoutes.verifyEmail, AppRoutes.pharmacistLogin, AppRoutes.pharmacistRegister, AppRoutes.adminLogin];
    test('open when signed out', () {
      for (final String r in routes) {
        expect(go(r, out), isNull, reason: r);
      }
    });
    test('signed-in users go to their home', () {
      for (final String r in routes) {
        expect(go(r, customer), AppRoutes.customerHome, reason: r);
        expect(go(r, admin), AppRoutes.adminDashboard, reason: r);
        expect(go(r, approved), AppRoutes.pharmacistDashboard, reason: r);
        expect(go(r, cashier), AppRoutes.pharmacistPos, reason: r);
        expect(go(r, pending), AppRoutes.statusPending, reason: r);
      }
    });
  });

  group('authentication', () {
    test('signed-out users are sent to welcome from any protected route', () {
      for (final String r in <String>[AppRoutes.customerHome, AppRoutes.pharmacistPos, AppRoutes.adminDashboard, '/customer/orders/abc', '/pharmacist/sales/xyz']) {
        expect(go(r, out), AppRoutes.welcome, reason: r);
      }
    });
    test('signed in but profile not loaded goes to splash', () {
      final SessionSnapshot s = snap(role: UserRole.customer, profile: false);
      expect(go(AppRoutes.customerHome, s), AppRoutes.splash);
    });
    test('suspended account goes to the suspended screen everywhere', () {
      final SessionSnapshot s = snap(role: UserRole.customer, suspended: true);
      expect(go(AppRoutes.customerHome, s), AppRoutes.accountSuspended);
      expect(go(AppRoutes.login, s), AppRoutes.accountSuspended);
      expect(go(AppRoutes.accountSuspended, s), isNull);
      final SessionSnapshot p = snap(role: UserRole.pharmacist, suspended: true, pharmacy: ApprovalStatus.approved);
      expect(go(AppRoutes.pharmacistPos, p), AppRoutes.accountSuspended);
    });
  });

  group('role separation', () {
    test('customer area only for customers', () {
      expect(go(AppRoutes.customerHome, customer), isNull);
      expect(go(AppRoutes.customerHome, admin), AppRoutes.accessDenied);
      expect(go(AppRoutes.customerHome, approved), AppRoutes.accessDenied);
      expect(go('/customer/orders/123/tracking', approved), AppRoutes.accessDenied);
    });
    test('admin area only for admins', () {
      expect(go(AppRoutes.adminDashboard, admin), isNull);
      expect(go(AppRoutes.adminDashboard, customer), AppRoutes.accessDenied);
      expect(go(AppRoutes.adminUsers, approved), AppRoutes.accessDenied);
      expect(go('/admin/pharmacies/abc', customer), AppRoutes.accessDenied);
    });
    test('pharmacist area is closed to admins and customers (except the registration wizard)', () {
      expect(go(AppRoutes.pharmacistPos, admin), AppRoutes.accessDenied);
      expect(go(AppRoutes.pharmacistPos, customer), AppRoutes.accessDenied);
      expect(go(AppRoutes.pharmacyRegister, customer), isNull);
      expect(go(AppRoutes.pharmacyRegisterHours, customer), isNull);
      expect(go(AppRoutes.pharmacyRegister, admin), AppRoutes.accessDenied);
    });
  });

  group('pharmacy state machine', () {
    test('no pharmacy: only the wizard', () {
      expect(go(AppRoutes.pharmacistDashboard, noPharmacy), AppRoutes.pharmacyRegister);
      expect(go(AppRoutes.pharmacyRegisterAddress, noPharmacy), isNull);
    });
    test('pending: only the pending screen', () {
      expect(go(AppRoutes.statusPending, pending), isNull);
      expect(go(AppRoutes.pharmacistPos, pending), AppRoutes.statusPending);
      expect(go(AppRoutes.pharmacyRegister, pending), AppRoutes.statusPending);
      expect(go(AppRoutes.statusRejected, pending), AppRoutes.statusPending);
    });
    test('rejected: rejected screen and wizard (resubmit)', () {
      expect(go(AppRoutes.statusRejected, rejected), isNull);
      expect(go(AppRoutes.pharmacyRegister, rejected), isNull);
      expect(go(AppRoutes.pharmacistPos, rejected), AppRoutes.statusRejected);
    });
    test('suspended pharmacy: only the suspended screen', () {
      expect(go(AppRoutes.statusSuspended, suspendedPharmacy), isNull);
      expect(go(AppRoutes.pharmacistOrders, suspendedPharmacy), AppRoutes.statusSuspended);
    });
    test('approved: operational routes open, wizard and status screens redirect home', () {
      expect(go(AppRoutes.pharmacistPos, approved), isNull);
      expect(go('/pharmacist/orders/abc/handover', approved), isNull);
      expect(go(AppRoutes.pharmacyRegister, approved), AppRoutes.pharmacistDashboard);
      expect(go(AppRoutes.statusPending, approved), AppRoutes.pharmacistDashboard);
    });
  });

  group('cashier restrictions', () {
    test('blocked from money, catalogue and list changes, imports and pharmacy settings', () {
      for (final String r in <String>[
        AppRoutes.pharmacistDashboard,
        AppRoutes.productAdd,
        AppRoutes.productPropose,
        AppRoutes.productImport,
        '/pharmacist/products/abc/edit',
        AppRoutes.settingsProfile,
        AppRoutes.settingsContact,
        AppRoutes.settingsHours,
        AppRoutes.settingsLocation,
      ]) {
        expect(go(r, cashier), AppRoutes.accessDenied, reason: r);
        expect(go(r, approved), isNull, reason: r);
      }
    });
    test('can sell, handle orders, browse products, answer customer requests, change own password', () {
      for (final String r in <String>[
        AppRoutes.pharmacistPos,
        AppRoutes.posCheckout,
        AppRoutes.pharmacistOrders,
        '/pharmacist/orders/abc',
        AppRoutes.pharmacistProducts,
        '/pharmacist/products/abc',
        AppRoutes.pharmacistRequests,
        '/pharmacist/requests/abc',
        AppRoutes.salesHistory,
        AppRoutes.settingsSecurity,
        AppRoutes.pharmacistSettings,
      ]) {
        expect(go(r, cashier), isNull, reason: r);
      }
    });
    test('the stock screens of the old inventory model no longer exist as routes', () {
      expect(AppRoutes.all.where((String r) => r.contains('/stock') || r.contains('inventory')), isEmpty);
    });
  });

  group('customer requests ("ask nearby")', () {
    test('customers open their requests list and one request', () {
      expect(go(AppRoutes.customerRequests, customer), isNull);
      expect(go('/customer/requests/abc', customer), isNull);
    });
    test('nobody else does', () {
      for (final SessionSnapshot s in <SessionSnapshot>[admin, approved, cashier]) {
        expect(go(AppRoutes.customerRequests, s), AppRoutes.accessDenied);
        expect(go('/customer/requests/abc', s), AppRoutes.accessDenied);
      }
      expect(go(AppRoutes.customerRequests, out), AppRoutes.welcome);
    });
    test('the pharmacy inbox is closed to customers and admins and to pharmacies that are not approved', () {
      expect(go(AppRoutes.pharmacistRequests, approved), isNull);
      expect(go('/pharmacist/requests/abc', approved), isNull);
      expect(go(AppRoutes.pharmacistRequests, customer), AppRoutes.accessDenied);
      expect(go(AppRoutes.pharmacistRequests, admin), AppRoutes.accessDenied);
      expect(go(AppRoutes.pharmacistRequests, pending), AppRoutes.statusPending);
      expect(go(AppRoutes.pharmacistRequests, suspendedPharmacy), AppRoutes.statusSuspended);
    });
  });

  group('path normalisation', () {
    test('query strings and trailing slashes do not change the decision', () {
      expect(go('/customer/home?tab=2', customer), isNull);
      expect(go('/customer/home/', out), AppRoutes.welcome);
      expect(go('/login?x=1', customer), AppRoutes.customerHome);
    });
    test('unknown areas are left to the router', () {
      expect(go('/something/else', customer), isNull);
    });
  });

  group('homeFor', () {
    test('every state', () {
      expect(RoutePolicy.homeFor(out), AppRoutes.welcome);
      expect(RoutePolicy.homeFor(customer), AppRoutes.customerHome);
      expect(RoutePolicy.homeFor(admin), AppRoutes.adminDashboard);
      expect(RoutePolicy.homeFor(noPharmacy), AppRoutes.pharmacyRegister);
      expect(RoutePolicy.homeFor(pending), AppRoutes.statusPending);
      expect(RoutePolicy.homeFor(rejected), AppRoutes.statusRejected);
      expect(RoutePolicy.homeFor(suspendedPharmacy), AppRoutes.statusSuspended);
      expect(RoutePolicy.homeFor(approved), AppRoutes.pharmacistDashboard);
      expect(RoutePolicy.homeFor(cashier), AppRoutes.pharmacistPos);
    });
    test('a home route is always allowed for its own session (no redirect loops)', () {
      for (final SessionSnapshot s in <SessionSnapshot>[customer, admin, noPharmacy, pending, rejected, suspendedPharmacy, approved, cashier, snap(role: UserRole.customer, suspended: true)]) {
        expect(RoutePolicy.redirectFor(RoutePolicy.homeFor(s), s), isNull, reason: RoutePolicy.homeFor(s));
      }
    });
  });
}
