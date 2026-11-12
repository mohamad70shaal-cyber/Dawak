import 'enums.dart';
import 'geo.dart';
import 'json_utils.dart';

/// One weekday of opening hours. `day` is 0 = Saturday … 6 = Friday (the Syrian week).
class DayHours {
  const DayHours({required this.day, required this.open, this.from = '09:00', this.to = '21:00'});

  final int day;
  final bool open;
  final String from;
  final String to;

  Map<String, dynamic> toJson() => <String, dynamic>{'day': day, 'open': open, 'from': from, 'to': to};

  factory DayHours.fromJson(Map<String, dynamic> j) => DayHours(
        day: J.integer(j['day']),
        open: J.boolean(j['open']),
        from: J.str(j['from'], '09:00'),
        to: J.str(j['to'], '21:00'),
      );

  DayHours copyWith({bool? open, String? from, String? to}) =>
      DayHours(day: day, open: open ?? this.open, from: from ?? this.from, to: to ?? this.to);
}

class OpeningHours {
  const OpeningHours(this.days);

  final List<DayHours> days;

  /// Default schedule: open every day except Friday, 09:00–21:00.
  factory OpeningHours.defaults() => OpeningHours(
        List<DayHours>.generate(7, (int i) => DayHours(day: i, open: i != 6)),
      );

  /// Stored as `{"days": [ {day, open, from, to}, ... ]}`.
  Map<String, dynamic> toJson() => <String, dynamic>{'days': days.map((DayHours d) => d.toJson()).toList()};

  factory OpeningHours.fromJson(Object? raw) {
    final Map<String, dynamic> m = J.map(raw);
    final List<Map<String, dynamic>> list = J.list(m['days']);
    if (list.isEmpty) return OpeningHours.defaults();
    final List<DayHours> parsed = list.map(DayHours.fromJson).toList();
    final Map<int, DayHours> byDay = <int, DayHours>{for (final DayHours d in parsed) d.day: d};
    return OpeningHours(List<DayHours>.generate(7, (int i) => byDay[i] ?? DayHours(day: i, open: false)));
  }
}

/// A pharmacy as seen by its owner/members and by admins (full row).
class Pharmacy {
  const Pharmacy({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.phone,
    required this.showPhonePublicly,
    required this.addressLine,
    required this.neighborhood,
    required this.city,
    required this.directions,
    required this.hours,
    required this.currency,
    required this.status,
    required this.isListed,
    this.location,
    this.statusReason,
    this.licensePath,
    this.submittedAt,
    this.reviewedAt,
    this.createdAt,
    this.memberRole,
  });

  final String id;
  final String ownerId;
  final String name;
  final String phone;
  final bool showPhonePublicly;
  final String addressLine;
  final String neighborhood;
  final String city;
  final String directions;
  final OpeningHours hours;
  final String currency;
  final ApprovalStatus status;
  final bool isListed;

  /// Where the shop is (required at registration; null only for rows created before locations existed).
  final GeoPoint? location;
  final String? statusReason;
  final String? licensePath;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  /// The signed-in user's role in this pharmacy (null for admins).
  final MemberRole? memberRole;

  bool get isApproved => status == ApprovalStatus.approved;

  String get fullAddress => <String>[addressLine, neighborhood, city].where((String s) => s.trim().isNotEmpty).join('، ');

  factory Pharmacy.fromJson(Map<String, dynamic> j, {MemberRole? memberRole}) => Pharmacy(
        id: J.str(j['id']),
        ownerId: J.str(j['owner_id']),
        name: J.str(j['name']),
        phone: J.str(j['phone']),
        showPhonePublicly: J.boolean(j['show_phone_publicly'], true),
        addressLine: J.str(j['address_line']),
        neighborhood: J.str(j['neighborhood']),
        city: J.str(j['city']),
        directions: J.str(j['directions']),
        hours: OpeningHours.fromJson(j['opening_hours']),
        currency: J.str(j['currency'], 'SYP'),
        status: ApprovalStatus.parse(J.strOrNull(j['approval_status'])),
        isListed: J.boolean(j['is_listed']),
        location: GeoPoint.tryCreate(j['latitude'], j['longitude']),
        statusReason: J.strOrNull(j['status_reason']),
        licensePath: J.strOrNull(j['license_document_path']),
        submittedAt: J.date(j['submitted_at']),
        reviewedAt: J.date(j['reviewed_at']),
        createdAt: J.date(j['created_at']),
        memberRole: memberRole,
      );
}

/// Draft used by the registration wizard and by "edit pharmacy" screens.
class PharmacyDraft {
  PharmacyDraft({
    this.name = '',
    this.phone = '',
    this.showPhonePublicly = true,
    this.addressLine = '',
    this.neighborhood = '',
    this.city = '',
    this.directions = '',
    OpeningHours? hours,
    this.currency = 'SYP',
    this.licensePath,
    this.location,
  }) : hours = hours ?? OpeningHours.defaults();

  String name;
  String phone;
  bool showPhonePublicly;
  String addressLine;
  String neighborhood;
  String city;
  String directions;
  OpeningHours hours;
  String currency;

  /// Storage path of the uploaded licence (`<user-id>/<file>`), set after a successful upload.
  String? licensePath;

  /// The shop's position, taken from the device GPS or a pasted map link. Required to register.
  GeoPoint? location;

  factory PharmacyDraft.fromPharmacy(Pharmacy p) => PharmacyDraft(
        name: p.name,
        phone: p.phone,
        showPhonePublicly: p.showPhonePublicly,
        addressLine: p.addressLine,
        neighborhood: p.neighborhood,
        city: p.city,
        directions: p.directions,
        hours: p.hours,
        currency: p.currency,
        licensePath: p.licensePath,
        location: p.location,
      );
}

/// What customers may see about a pharmacy (masked; from the public RPCs).
class PublicPharmacy {
  const PublicPharmacy({
    required this.id,
    required this.name,
    required this.city,
    required this.neighborhood,
    required this.addressLine,
    required this.currency,
    this.phone,
    this.directions = '',
    this.hours,
    this.location,
    this.distanceKm,
  });

  final String id;
  final String name;
  final String city;
  final String neighborhood;
  final String addressLine;
  final String currency;
  final String? phone;
  final String directions;
  final OpeningHours? hours;

  /// Used for "open in maps / directions".
  final GeoPoint? location;

  /// Distance from the customer's position when the server was given one.
  final double? distanceKm;

  String get fullAddress => <String>[addressLine, neighborhood, city].where((String s) => s.trim().isNotEmpty).join('، ');

  factory PublicPharmacy.fromJson(Map<String, dynamic> j) => PublicPharmacy(
        id: J.str(j['id'] ?? j['pharmacy_id']),
        name: J.str(j['name'] ?? j['pharmacy_name']),
        city: J.str(j['city']),
        neighborhood: J.str(j['neighborhood']),
        addressLine: J.str(j['address_line']),
        currency: J.str(j['currency'], 'SYP'),
        phone: J.strOrNull(j['phone']),
        directions: J.str(j['directions']),
        hours: j['opening_hours'] == null ? null : OpeningHours.fromJson(j['opening_hours']),
        location: GeoPoint.tryCreate(j['latitude'], j['longitude']),
        distanceKm: J.numberOrNull(j['distance_km']),
      );
}
