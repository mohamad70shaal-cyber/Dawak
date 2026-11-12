import '../datasources/api_client.dart';
import '../models/enums.dart';
import '../models/pharmacy.dart';
import '../models/profile.dart';
import '../../core/errors/app_failure.dart';

/// Authentication and the signed-in user's own profile / pharmacy.
class AuthRepository {
  AuthRepository(this._auth, this._api);

  final AuthGateway _auth;
  final ApiClient _api;

  bool get hasSession => _auth.hasSession;
  String? get currentUserId => _auth.currentUserId;
  String? get currentEmail => _auth.currentEmail;
  Stream<AuthEventKind> get events => _auth.events;

  Future<void> signIn(String email, String password) => _auth.signIn(email: email, password: password);

  Future<bool> signUp({required String email, required String password, required String displayName}) =>
      _auth.signUp(email: email, password: password, displayName: displayName);

  Future<void> signOut() => _auth.signOut();

  Future<void> resetPassword(String email) => _auth.resetPassword(email);

  Future<void> resendConfirmation(String email) => _auth.resendConfirmation(email);

  Future<void> updatePassword(String newPassword) => _auth.updatePassword(newPassword);

  /// The signed-in user's profile (RLS limits the table to the own row anyway).
  Future<Profile> myProfile() async {
    final String? id = _auth.currentUserId;
    if (id == null) throw const AppFailure('not_authenticated');
    final Map<String, dynamic>? row = await _api.selectOne(Query('profiles', eq: <String, Object>{'id': id}));
    if (row == null) throw const AppFailure('not_found');
    return Profile.fromJson(row);
  }

  Future<Profile> updateProfile({String? displayName, String? phone, String? locale}) async {
    final String? id = _auth.currentUserId;
    if (id == null) throw const AppFailure('not_authenticated');
    final Map<String, dynamic> values = <String, dynamic>{
      if (displayName != null) 'display_name': displayName.trim(),
      if (phone != null) 'phone': phone.trim().isEmpty ? null : phone.trim(),
      if (locale != null) 'locale': locale,
    };
    if (values.isNotEmpty) {
      final int n = await _api.update('profiles', values, eq: <String, Object>{'id': id});
      if (n == 0) throw const AppFailure('forbidden');
    }
    return myProfile();
  }

  /// The pharmacy the user belongs to (pharmacists), or null if none has been registered yet.
  Future<Pharmacy?> myPharmacy() async {
    final String? id = _auth.currentUserId;
    if (id == null) throw const AppFailure('not_authenticated');
    final Map<String, dynamic>? member = await _api.selectOne(Query(
      'pharmacy_members',
      eq: <String, Object>{'user_id': id, 'status': 'active'},
    ));
    if (member == null) return null;
    final Map<String, dynamic>? row = await _api.selectOne(Query(
      'pharmacies',
      eq: <String, Object>{'id': member['pharmacy_id'] as Object},
    ));
    if (row == null) return null;
    return Pharmacy.fromJson(row, memberRole: MemberRole.parse(member['role']?.toString()));
  }
}
