import 'enums.dart';
import 'json_utils.dart';

class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.suspended,
    required this.displayName,
    this.phone,
    this.locale = 'ar',
    this.suspendedReason,
    this.createdAt,
  });

  final String id;
  final UserRole role;
  final bool suspended;
  final String displayName;
  final String? phone;
  final String locale;
  final String? suspendedReason;
  final DateTime? createdAt;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: J.str(j['id']),
        role: UserRole.parse(J.strOrNull(j['role'])),
        suspended: J.str(j['account_status']) == 'suspended',
        displayName: J.str(j['display_name']),
        phone: J.strOrNull(j['phone']),
        locale: J.str(j['locale'], 'ar'),
        suspendedReason: J.strOrNull(j['suspended_reason']),
        createdAt: J.date(j['created_at']),
      );

  Profile copyWith({String? displayName, String? phone, String? locale}) => Profile(
        id: id,
        role: role,
        suspended: suspended,
        displayName: displayName ?? this.displayName,
        phone: phone ?? this.phone,
        locale: locale ?? this.locale,
        suspendedReason: suspendedReason,
        createdAt: createdAt,
      );
}
