import '../../data/models/enums.dart';
import 'app_routes.dart';
import 'session_snapshot.dart';

/// The whole guard table of `docs/navigation_matrix.md` §1 as pure functions.
///
/// `redirectFor` returns `null` when the route may be opened, otherwise the route to go to instead.
/// Guards are navigation convenience only: every protected action is re-authorised in PostgreSQL.
class RoutePolicy {
  const RoutePolicy._();

  static const Set<String> _public = <String>{
    AppRoutes.splash,
    AppRoutes.onboarding,
    AppRoutes.accessDenied,
    AppRoutes.notFound,
    AppRoutes.accountSuspended,
    AppRoutes.legalPrivacy,
    AppRoutes.legalTerms,
  };

  static const Set<String> _guestOnly = <String>{
    AppRoutes.welcome,
    AppRoutes.login,
    AppRoutes.register,
    AppRoutes.passwordReset,
    AppRoutes.verifyEmail,
    AppRoutes.pharmacistLogin,
    AppRoutes.pharmacistRegister,
    AppRoutes.adminLogin,
  };

  /// Pharmacist routes that cashiers may not open (money, catalogue and list changes, settings). Cashiers may open the
  /// requests inbox and answer ("available" / "unavailable"): the server keeps their answers out of the pharmacy's list.
  static final List<RegExp> _managerOnly = <RegExp>[
    RegExp(r'^/pharmacist/dashboard$'),
    RegExp(r'^/pharmacist/products/(add|propose|import)$'),
    RegExp(r'^/pharmacist/products/[^/]+/edit$'),
    RegExp(r'^/pharmacist/settings/(profile|contact|hours|location)$'),
  ];

  /// Strips query string, fragment and a trailing slash so `'/customer/home?x=1'` and `'/customer/home/'`
  /// classify like `'/customer/home'`.
  static String normalize(String route) {
    String p = route;
    final int q = p.indexOf('?');
    if (q >= 0) p = p.substring(0, q);
    final int h = p.indexOf('#');
    if (h >= 0) p = p.substring(0, h);
    if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p.isEmpty ? '/' : p;
  }

  static bool isPublic(String path) => _public.contains(path);

  static bool isGuestOnly(String path) => _guestOnly.contains(path);

  static bool isWizard(String path) => path.startsWith(AppRoutes.pharmacyRegister);

  static bool isStatus(String path) => path.startsWith('/pharmacist/status/');

  static bool isManagerOnly(String path) => _managerOnly.any((RegExp r) => r.hasMatch(path));

  /// The first screen for a signed-in user (or the welcome screen when signed out).
  static String homeFor(SessionSnapshot s) {
    if (!s.signedIn) return AppRoutes.welcome;
    if (!s.profileLoaded) return AppRoutes.splash;
    if (s.accountSuspended) return AppRoutes.accountSuspended;
    switch (s.role!) {
      case UserRole.admin:
        return AppRoutes.adminDashboard;
      case UserRole.customer:
        return AppRoutes.customerHome;
      case UserRole.pharmacist:
        return _pharmacistHome(s);
    }
  }

  static String _pharmacistHome(SessionSnapshot s) {
    switch (s.pharmacyState) {
      case PharmacyState.none:
        return AppRoutes.pharmacyRegister;
      case PharmacyState.pending:
        return AppRoutes.statusPending;
      case PharmacyState.rejected:
        return AppRoutes.statusRejected;
      case PharmacyState.suspended:
        return AppRoutes.statusSuspended;
      case PharmacyState.approved:
        return s.canManagePharmacy ? AppRoutes.pharmacistDashboard : AppRoutes.pharmacistPos;
    }
  }

  /// `null` = allowed.
  static String? redirectFor(String route, SessionSnapshot s) {
    final String path = normalize(route);

    if (isPublic(path)) return null;

    if (isGuestOnly(path)) {
      return s.signedIn ? homeFor(s) : null;
    }

    // Everything else needs a session.
    if (!s.signedIn) return AppRoutes.welcome;
    if (!s.profileLoaded) return AppRoutes.splash;
    if (s.accountSuspended) return AppRoutes.accountSuspended;

    final UserRole role = s.role!;

    if (path.startsWith('/customer/')) {
      return role == UserRole.customer ? null : AppRoutes.accessDenied;
    }
    if (path.startsWith('/admin/')) {
      return role == UserRole.admin ? null : AppRoutes.accessDenied;
    }
    if (path.startsWith('/pharmacist/')) {
      return _pharmacistRedirect(path, s);
    }

    // Unknown area: let the router's unknownRoute handle it.
    return null;
  }

  static String? _pharmacistRedirect(String path, SessionSnapshot s) {
    final UserRole role = s.role!;
    if (role == UserRole.admin) return AppRoutes.accessDenied;

    // A customer account may only open the registration wizard (that is how it becomes a pharmacist).
    if (role == UserRole.customer) {
      if (isWizard(path) && s.pharmacyState == PharmacyState.none) return null;
      return AppRoutes.accessDenied;
    }

    final PharmacyState st = s.pharmacyState;
    switch (st) {
      case PharmacyState.none:
        return isWizard(path) ? null : AppRoutes.pharmacyRegister;
      case PharmacyState.pending:
        return path == AppRoutes.statusPending ? null : AppRoutes.statusPending;
      case PharmacyState.rejected:
        if (path == AppRoutes.statusRejected || isWizard(path)) return null;
        return AppRoutes.statusRejected;
      case PharmacyState.suspended:
        return path == AppRoutes.statusSuspended ? null : AppRoutes.statusSuspended;
      case PharmacyState.approved:
        if (isWizard(path) || isStatus(path)) return homeFor(s);
        if (!s.canManagePharmacy && isManagerOnly(path)) return AppRoutes.accessDenied;
        return null;
    }
  }
}
