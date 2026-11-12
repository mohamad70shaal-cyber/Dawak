import '../../core/utils/phone_utils.dart';
import '../datasources/api_client.dart';
import '../models/geo.dart';
import '../models/json_utils.dart';
import '../models/pharmacy.dart';
import '../models/platform.dart';

/// Pharmacy registration, own-pharmacy edits and the public directory.
class PharmacyRepository {
  PharmacyRepository(this._api);

  final ApiClient _api;

  Future<Pharmacy> register(PharmacyDraft d) async {
    final dynamic r = await _api.rpc('register_pharmacy', <String, dynamic>{
      'p_name': d.name.trim(),
      'p_phone': cleanPhone(d.phone) ?? d.phone.trim(),
      'p_address_line': d.addressLine.trim(),
      'p_neighborhood': d.neighborhood.trim(),
      'p_city': d.city.trim(),
      'p_directions': d.directions.trim(),
      'p_opening_hours': d.hours.toJson(),
      'p_currency': d.currency,
      'p_license_path': d.licensePath,
      'p_latitude': d.location?.latitude,
      'p_longitude': d.location?.longitude,
      'p_show_phone_publicly': d.showPhonePublicly,
    });
    return Pharmacy.fromJson(J.map(r));
  }

  Future<Pharmacy> resubmit(String pharmacyId, PharmacyDraft d) async {
    final dynamic r = await _api.rpc('resubmit_pharmacy', <String, dynamic>{
      'p_pharmacy_id': pharmacyId,
      'p_name': d.name.trim(),
      'p_phone': cleanPhone(d.phone) ?? d.phone.trim(),
      'p_address_line': d.addressLine.trim(),
      'p_neighborhood': d.neighborhood.trim(),
      'p_city': d.city.trim(),
      'p_directions': d.directions.trim(),
      'p_opening_hours': d.hours.toJson(),
      'p_license_path': d.licensePath,
      'p_show_phone_publicly': d.showPhonePublicly,
      if (d.location != null) 'p_latitude': d.location!.latitude,
      if (d.location != null) 'p_longitude': d.location!.longitude,
    });
    return Pharmacy.fromJson(J.map(r));
  }

  /// Owner edits of an approved pharmacy. Only non-null arguments change.
  Future<Pharmacy> updateMine(
    String pharmacyId, {
    String? name,
    String? phone,
    String? addressLine,
    String? neighborhood,
    String? city,
    String? directions,
    OpeningHours? hours,
    bool? showPhonePublicly,
    bool? isListed,
    GeoPoint? location,
  }) async {
    final dynamic r = await _api.rpc('update_my_pharmacy', <String, dynamic>{
      'p_pharmacy_id': pharmacyId,
      if (name != null) 'p_name': name.trim(),
      if (phone != null) 'p_phone': cleanPhone(phone) ?? phone.trim(),
      if (addressLine != null) 'p_address_line': addressLine.trim(),
      if (neighborhood != null) 'p_neighborhood': neighborhood.trim(),
      if (city != null) 'p_city': city.trim(),
      if (directions != null) 'p_directions': directions.trim(),
      if (hours != null) 'p_opening_hours': hours.toJson(),
      if (showPhonePublicly != null) 'p_show_phone_publicly': showPhonePublicly,
      if (isListed != null) 'p_is_listed': isListed,
      if (location != null) 'p_latitude': location.latitude,
      if (location != null) 'p_longitude': location.longitude,
    });
    return Pharmacy.fromJson(J.map(r));
  }

  /// Directory of approved, listed pharmacies. With [near] the server also returns each distance and sorts nearest first.
  Future<List<PublicPharmacy>> listPublic({String? query, String? city, GeoPoint? near, int limit = 20, int offset = 0}) async {
    final dynamic r = await _api.rpc('list_public_pharmacies', <String, dynamic>{
      'p_query': (query ?? '').trim().isEmpty ? null : query!.trim(),
      'p_city': (city ?? '').trim().isEmpty ? null : city!.trim(),
      'p_limit': limit,
      'p_offset': offset,
      'p_latitude': near?.latitude,
      'p_longitude': near?.longitude,
    });
    return J.list(r).map(PublicPharmacy.fromJson).toList();
  }

  Future<PublicPharmacy> getPublic(String pharmacyId) async {
    final dynamic r = await _api.rpc('get_public_pharmacy', <String, dynamic>{'p_pharmacy_id': pharmacyId});
    return PublicPharmacy.fromJson(J.map(r));
  }

  // ---- admin ---------------------------------------------------------------------------------------------

  /// Admin list of pharmacies, optionally by status. Owner names are fetched in a second query because admins may
  /// read non-customer profiles.
  Future<List<PharmacyApplication>> adminList({String? status, String? text, int limit = 50, int offset = 0}) async {
    final String t = (text ?? '').trim().replaceAll(RegExp(r'[,()*%]'), ' ').trim();
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'pharmacies',
      eq: status == null ? const <String, Object>{} : <String, Object>{'approval_status': status},
      orFilter: t.isEmpty ? null : 'name.ilike.*$t*,city.ilike.*$t*,neighborhood.ilike.*$t*,phone.ilike.*$t*',
      orderBy: 'submitted_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    if (rows.isEmpty) return <PharmacyApplication>[];
    final List<Object> ownerIds = rows.map((Map<String, dynamic> r) => J.str(r['owner_id'])).toSet().cast<Object>().toList();
    final List<Map<String, dynamic>> owners = await _api.select(Query('profiles', inList: <String, List<Object>>{'id': ownerIds}));
    final Map<String, Map<String, dynamic>> byId = <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> o in owners) J.str(o['id']): o,
    };
    return rows.map((Map<String, dynamic> r) {
      final Map<String, dynamic>? o = byId[J.str(r['owner_id'])];
      return PharmacyApplication(
        pharmacy: Pharmacy.fromJson(r),
        ownerName: o == null ? '' : J.str(o['display_name']),
        ownerPhone: o == null ? null : J.strOrNull(o['phone']),
      );
    }).toList();
  }

  Future<PharmacyApplication?> adminGet(String pharmacyId) async {
    final Map<String, dynamic>? row = await _api.selectOne(Query('pharmacies', eq: <String, Object>{'id': pharmacyId}));
    if (row == null) return null;
    final Map<String, dynamic>? owner =
        await _api.selectOne(Query('profiles', eq: <String, Object>{'id': J.str(row['owner_id'])}));
    return PharmacyApplication(
      pharmacy: Pharmacy.fromJson(row),
      ownerName: owner == null ? '' : J.str(owner['display_name']),
      ownerPhone: owner == null ? null : J.strOrNull(owner['phone']),
    );
  }

  /// `decision`: approve | reject | suspend | reinstate. A reason is required for reject and suspend.
  Future<void> adminReview(String pharmacyId, String decision, {String? reason}) async {
    await _api.rpc('admin_review_pharmacy', <String, dynamic>{
      'p_pharmacy_id': pharmacyId,
      'p_decision': decision,
      'p_reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
    });
  }
}
