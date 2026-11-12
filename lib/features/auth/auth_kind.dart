import '../../app/routes/app_routes.dart';
import '../../data/models/enums.dart';

/// Which door the user came through. The same login/registration screens serve all three.
enum AuthKind {
  customer,
  pharmacist,
  admin;

  String get loginRoute {
    switch (this) {
      case AuthKind.customer:
        return AppRoutes.login;
      case AuthKind.pharmacist:
        return AppRoutes.pharmacistLogin;
      case AuthKind.admin:
        return AppRoutes.adminLogin;
    }
  }

  String get registerRoute => this == AuthKind.pharmacist ? AppRoutes.pharmacistRegister : AppRoutes.register;

  /// Whether a profile with [role] (and, for pharmacists, [hasPharmacy]) may use this door.
  ///
  /// A customer-role account without a pharmacy may enter the pharmacist door: that is the state right after
  /// pharmacist sign-up, before the registration wizard promotes it to the pharmacist role.
  bool accepts(UserRole role, {required bool hasPharmacy}) {
    switch (this) {
      case AuthKind.customer:
        return role == UserRole.customer;
      case AuthKind.pharmacist:
        return role == UserRole.pharmacist || (role == UserRole.customer && !hasPharmacy);
      case AuthKind.admin:
        return role == UserRole.admin;
    }
  }

  /// Translation key of the "wrong door" message.
  String get wrongRoleKey => 'auth_wrong_role_$name';
}
