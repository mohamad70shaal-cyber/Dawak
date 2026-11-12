import 'dart:async';

import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../app/routes/route_policy.dart';
import '../../app/routes/session_snapshot.dart';
import '../../data/datasources/api_client.dart';
import '../../data/models/enums.dart';
import '../../data/models/pharmacy.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../errors/app_failure.dart';

/// Owns "who is signed in": profile, pharmacy and member role. Every guard, shell and controller reads it.
///
/// - [restore] runs at start-up (splash) and after sign-in.
/// - It listens to auth events: a sign-out or a failed refresh clears the state and returns to the welcome screen.
/// - A pharmacist whose application is pending is polled every [pollInterval]; approval takes effect without a restart.
class SessionService extends GetxService {
  SessionService(this._auth, {void Function(String route)? navigate, this.pollInterval = const Duration(seconds: 30)})
      : _navigate = navigate ?? _defaultNavigate;

  final AuthRepository _auth;
  final void Function(String route) _navigate;
  final Duration pollInterval;

  final Rx<SessionSnapshot> _state = SessionSnapshot.signedOut.obs;
  StreamSubscription<AuthEventKind>? _sub;
  Timer? _poll;
  String? _blockedTarget;
  bool _busy = false;

  /// Set when the user was sent to the welcome screen because the session ended (not by pressing "sign out").
  final RxBool sessionExpired = false.obs;

  static void _defaultNavigate(String route) => Get.offAllNamed<dynamic>(route);

  SessionSnapshot get snapshot => _state.value;

  /// Reactive view for widgets (`Obx(() => session.state.value ...)`).
  Rx<SessionSnapshot> get state => _state;

  Profile? get profile => _state.value.profile;
  Pharmacy? get pharmacy => _state.value.pharmacy;
  UserRole? get role => _state.value.role;
  MemberRole? get memberRole => _state.value.memberRole;
  bool get signedIn => _state.value.signedIn;
  String get email => _auth.currentEmail ?? '';
  String get homeRoute => RoutePolicy.homeFor(_state.value);

  @override
  void onInit() {
    super.onInit();
    _sub = _auth.events.listen(_onAuthEvent);
  }

  @override
  void onClose() {
    _sub?.cancel();
    _poll?.cancel();
    super.onClose();
  }

  void _onAuthEvent(AuthEventKind e) {
    if (e == AuthEventKind.signedOut && _state.value.signedIn && !_busy) {
      // The session ended underneath us (expired refresh token, revoked, signed out elsewhere).
      _clear();
      sessionExpired.value = true;
      _navigate(AppRoutes.welcome);
    }
  }

  /// Loads the profile (and the pharmacy for pharmacists) for the current Supabase session.
  /// Throws [AppFailure] when the profile cannot be read; the splash screen shows a retry in that case.
  Future<SessionSnapshot> restore() async {
    if (!_auth.hasSession) {
      _clear();
      return _state.value;
    }
    final Profile p = await _auth.myProfile();
    Pharmacy? ph;
    if (p.role == UserRole.pharmacist && !p.suspended) {
      ph = await _auth.myPharmacy();
    }
    _state.value = SessionSnapshot(signedIn: true, profile: p, pharmacy: ph);
    _syncPolling();
    return _state.value;
  }

  /// Re-reads profile and pharmacy; navigates to the new home when the account state changed
  /// (approved, rejected, suspended, ...). Failures are swallowed: the next poll or action retries.
  Future<void> refresh({bool navigateOnChange = true}) async {
    if (!_auth.hasSession) return;
    final String before = homeRoute;
    try {
      await restore();
    } on AppFailure catch (e) {
      if (e.isSessionProblem) await signOut(expired: true);
      return;
    }
    if (navigateOnChange && homeRoute != before) _navigate(homeRoute);
  }

  /// Called by controllers when a server call failed with a code that changes what the user may do.
  Future<void> handleFailure(AppFailure f) async {
    if (f.code == 'account_suspended') {
      await refresh();
    } else if (f.code == 'not_authenticated') {
      await signOut(expired: true);
    }
  }

  Future<void> signOut({bool expired = false}) async {
    _busy = true;
    try {
      await _auth.signOut();
    } on AppFailure {
      // Local state is cleared regardless: the user asked to leave.
    } finally {
      _busy = false;
    }
    _clear();
    sessionExpired.value = expired;
    _navigate(AppRoutes.welcome);
  }

  /// Ends the Supabase session without navigating (used when a login is rejected, e.g. wrong role, and the
  /// login screen stays open to show why).
  Future<void> discardSession() async {
    _busy = true;
    try {
      await _auth.signOut();
    } on AppFailure {
      // Nothing more to do: the local state is cleared below either way.
    } finally {
      _busy = false;
    }
    _clear();
  }

  void _clear() {
    _state.value = SessionSnapshot.signedOut;
    _blockedTarget = null;
    _poll?.cancel();
    _poll = null;
  }

  void _syncPolling() {
    final bool needPoll = _state.value.pharmacyState == PharmacyState.pending;
    if (needPoll && _poll == null) {
      _poll = Timer.periodic(pollInterval, (Timer _) => refresh());
    } else if (!needPoll && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  // ---- deep-link resume ---------------------------------------------------------------------------------

  /// The middleware calls this when it blocks a navigation, so a deep link survives the login detour.
  void rememberBlockedTarget(String route) {
    final String path = RoutePolicy.normalize(route);
    if (!_state.value.signedIn && !RoutePolicy.isPublic(path) && !RoutePolicy.isGuestOnly(path)) {
      _blockedTarget = route;
    }
  }

  /// Where to go after a successful sign-in: the remembered deep link when this user may open it,
  /// otherwise the role home. Consumes the remembered target.
  String routeAfterLogin() {
    final String? t = _blockedTarget;
    _blockedTarget = null;
    if (t != null && RoutePolicy.redirectFor(t, _state.value) == null) return t;
    return homeRoute;
  }
}
