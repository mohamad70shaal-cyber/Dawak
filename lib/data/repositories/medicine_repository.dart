import '../datasources/api_client.dart';
import '../models/geo.dart';
import '../models/json_utils.dart';
import '../models/medicine.dart';

/// The shared medicine catalogue: customer search, pharmacist picking/proposing, admin curation.
class MedicineRepository {
  MedicineRepository(this._api);

  final ApiClient _api;

  Future<List<MedicineCategory>> categories({bool includeInactive = false}) async {
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'medicine_categories',
      eq: includeInactive ? const <String, Object>{} : <String, Object>{'is_active': true},
      orderBy: 'sort_order',
      secondOrderBy: 'name_ar',
    ));
    return rows.map(MedicineCategory.fromJson).toList();
  }

  /// Customer / pharmacist search (normalised Arabic and Latin, ranked). Query shorter than 2 characters returns [].
  Future<List<Medicine>> search(String query, {String? categoryId, String? dosageForm, int limit = 20, int offset = 0}) async {
    final dynamic r = await _api.rpc('search_medicines', <String, dynamic>{
      'p_query': query.trim(),
      'p_category_id': categoryId,
      'p_dosage_form': (dosageForm ?? '').trim().isEmpty ? null : dosageForm!.trim(),
      'p_limit': limit,
      'p_offset': offset,
    });
    return J.list(r).map(Medicine.fromJson).toList();
  }

  Future<Medicine?> getById(String id) async {
    final Map<String, dynamic>? row = await _api.selectOne(Query('medicines', eq: <String, Object>{'id': id}));
    return row == null ? null : Medicine.fromJson(row);
  }

  /// Pharmacies that confirmed [medicineId] as available within the last 30 days. With [near] the server adds each
  /// pharmacy's distance and sorts nearest first (optionally only within [radiusKm]); without it, recent first then cheapest.
  Future<List<MedicineOffer>> offers(String medicineId,
      {String? city, GeoPoint? near, double? radiusKm, int limit = 20, int offset = 0}) async {
    final dynamic r = await _api.rpc('get_medicine_pharmacies', <String, dynamic>{
      'p_medicine_id': medicineId,
      'p_latitude': near?.latitude,
      'p_longitude': near?.longitude,
      'p_radius_km': near == null ? null : radiusKm,
      'p_city': (city ?? '').trim().isEmpty ? null : city!.trim(),
      'p_limit': limit,
      'p_offset': offset,
    });
    return J.list(r).map(MedicineOffer.fromJson).toList();
  }

  Future<List<PublicProduct>> pharmacyCatalogue(String pharmacyId,
      {String? query, String? categoryId, int limit = 20, int offset = 0}) async {
    final dynamic r = await _api.rpc('get_public_pharmacy_products', <String, dynamic>{
      'p_pharmacy_id': pharmacyId,
      'p_query': (query ?? '').trim().isEmpty ? null : query!.trim(),
      'p_category_id': categoryId,
      'p_limit': limit,
      'p_offset': offset,
    });
    return J.list(r).map(PublicProduct.fromJson).toList();
  }

  /// Pharmacist proposal. Returns the medicine id (an existing one when the catalogue already has it) and
  /// whether it already existed.
  Future<({String id, String status, bool existed})> propose(MedicineDraft d) async {
    final dynamic r = await _api.rpc('propose_medicine', <String, dynamic>{
      'p_name_ar': d.nameAr,
      'p_name_en': d.nameEn,
      'p_brand_name': d.brandName,
      'p_active_ingredient': d.activeIngredient,
      'p_strength': d.strength,
      'p_dosage_form': d.dosageForm,
      'p_package_description': d.packageDescription,
      'p_category_id': d.categoryId,
    });
    final Map<String, dynamic> m = J.map(r);
    return (id: J.str(m['id']), status: J.str(m['catalog_status']), existed: J.boolean(m['existed']));
  }

  // ---- admin ---------------------------------------------------------------------------------------------

  /// Admin list by status (`pending`, `approved`, `rejected`, `archived`) with optional name filter.
  Future<List<Medicine>> adminList({String? status, String? text, int limit = 50, int offset = 0}) async {
    final String t = (text ?? '').trim().replaceAll(RegExp(r'[,()*%]'), ' ').trim();
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'medicines',
      eq: status == null ? const <String, Object>{} : <String, Object>{'catalog_status': status},
      orFilter: t.isEmpty ? null : 'name_ar.ilike.*$t*,name_en.ilike.*$t*,brand_name.ilike.*$t*',
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    return rows.map(Medicine.fromJson).toList();
  }

  Future<void> adminCreate(MedicineDraft d, {String status = 'approved'}) async {
    await _api.insertOnly('medicines', <String, dynamic>{...d.toRow(), 'catalog_status': status});
  }

  Future<void> adminUpdate(String id, MedicineDraft d) async {
    final int n = await _api.update('medicines', d.toRow(), eq: <String, Object>{'id': id});
    if (n == 0) throw StateError('medicine_not_updated');
  }

  /// `decision`: approve | reject | archive.
  Future<void> adminReview(String id, String decision) async {
    await _api.rpc('admin_review_medicine', <String, dynamic>{'p_medicine_id': id, 'p_decision': decision});
  }

  Future<void> saveCategory({String? id, required String nameAr, String? nameEn, int sortOrder = 0, bool isActive = true}) async {
    final Map<String, dynamic> values = <String, dynamic>{
      'name_ar': nameAr.trim(),
      'name_en': (nameEn ?? '').trim().isEmpty ? null : nameEn!.trim(),
      'sort_order': sortOrder,
      'is_active': isActive,
    };
    if (id == null) {
      await _api.insertOnly('medicine_categories', values);
    } else {
      final int n = await _api.update('medicine_categories', values, eq: <String, Object>{'id': id});
      if (n == 0) throw StateError('category_not_updated');
    }
  }
}
