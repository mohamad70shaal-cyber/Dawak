import '../../data/models/enums.dart';
import '../../data/models/pharmacy.dart';
import '../../data/models/profile.dart';

/// Where a pharmacist stands in the registration / approval process.
enum PharmacyState { none, pending, approved, rejected, suspended }

/// An immutable picture of "who is signed in" that the route policy decides on. Keeping it a plain value
/// (no GetX, no Supabase) is what makes the guard rules unit-testable.
class SessionSnapshot {
  const SessionSnapshot({this.signedIn = false, this.profile, this.pharmacy});

  static const SessionSnapshot signedOut = SessionSnapshot();

  final bool signedIn;

  /// Null while the profile has not been loaded (or could not be) for a signed-in user.
  final Profile? profile;

  /// The pharmacy the user belongs to, if any.
  final Pharmacy? pharmacy;

  bool get profileLoaded => profile != null;

  UserRole? get role => profile?.role;

  bool get accountSuspended => profile?.suspended ?? false;

  MemberRole? get memberRole => pharmacy?.memberRole;

  /// Owners and managers manage the medicine list and money; cashiers do not.
  bool get canManagePharmacy => memberRole?.canManage ?? false;

  PharmacyState get pharmacyState {
    final Pharmacy? p = pharmacy;
    if (p == null) return PharmacyState.none;
    switch (p.status) {
      case ApprovalStatus.pending:
        return PharmacyState.pending;
      case ApprovalStatus.approved:
        return PharmacyState.approved;
      case ApprovalStatus.rejected:
        return PharmacyState.rejected;
      case ApprovalStatus.suspended:
        return PharmacyState.suspended;
    }
  }

  SessionSnapshot copyWith({bool? signedIn, Profile? profile, Pharmacy? pharmacy, bool clearPharmacy = false}) =>
      SessionSnapshot(
        signedIn: signedIn ?? this.signedIn,
        profile: profile ?? this.profile,
        pharmacy: clearPharmacy ? null : (pharmacy ?? this.pharmacy),
      );
}
