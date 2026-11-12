import '../datasources/api_client.dart';
import '../models/json_utils.dart';
import '../models/medicine.dart';

/// A medicine/price pair to import into the pharmacy's list.
class ListingEntry {
  const ListingEntry({required this.medicineId, required this.price});

  final String medicineId;
  final double price;
}

/// A pharmacy's own list of medicines (no quantities): what it says it has, and at which price.
/// Everything that changes the list goes through RPCs, so the server stamps `confirmed_at` and audits the change.
class ListingRepository {
  ListingRepository(this._api);

  final ApiClient _api;

  static const String _productColumns = '*, medicines(*)';

  /// `max_import_items` / `max_match_names` of the server: larger lists are sent in chunks of this size.
  static const int importChunk = 500;
  static const int matchChunk = 100;

  /// [filter]: `all` | `available` | `unavailable` | `stale` (available but not confirmed for a week).
  Future<List<PharmacyProduct>> products(
    String pharmacyId, {
    String? text,
    String filter = 'all',
    String? categoryId,
    int limit = 30,
    int offset = 0,
  }) async {
    final String t = (text ?? '').trim().replaceAll(RegExp(r'[,()*%]'), ' ').trim();
    final bool inner = t.isNotEmpty || categoryId != null;
    final Map<String, Object> eq = <String, Object>{
      'pharmacy_id': pharmacyId,
      if (filter == 'available' || filter == 'stale') 'is_available': true,
      if (filter == 'unavailable') 'is_available': false,
      if (categoryId != null) 'medicines.category_id': categoryId,
    };
    final Map<String, Object> lt = filter == 'stale'
        ? <String, Object>{
            'confirmed_at': DateTime.now().toUtc().subtract(const Duration(days: PharmacyProduct.freshDays)).toIso8601String(),
          }
        : const <String, Object>{};
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'pharmacy_products',
      columns: inner ? '*, medicines!inner(*)' : _productColumns,
      eq: eq,
      lt: lt,
      orFilter: t.isEmpty ? null : 'name_ar.ilike.*$t*,name_en.ilike.*$t*,brand_name.ilike.*$t*',
      orReferencedTable: t.isEmpty ? null : 'medicines',
      orderBy: 'updated_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    return rows.map(PharmacyProduct.fromJson).toList();
  }

  Future<PharmacyProduct?> product(String productId) async {
    final Map<String, dynamic>? row =
        await _api.selectOne(Query('pharmacy_products', columns: _productColumns, eq: <String, Object>{'id': productId}));
    return row == null ? null : PharmacyProduct.fromJson(row);
  }

  /// Items the cashier can sell: every product of the pharmacy (the shelf is the truth, so the "available" flag
  /// does not block a walk-in sale). Optional text search.
  Future<List<PharmacyProduct>> sellable(String pharmacyId, {String? text, int limit = 30, int offset = 0}) =>
      products(pharmacyId, text: text, limit: limit, offset: offset);

  /// Adds a catalogue medicine to the pharmacy's list (available, confirmed now) and returns the new product's id.
  /// When the pharmacy already lists it the server answers `invalid_input` with `details['reason'] == 'already_exists'`
  /// and `details['product_id']`.
  Future<String> addProduct({required String pharmacyId, required String medicineId, required double price}) async {
    final dynamic r = await _api.rpc('add_pharmacy_product', <String, dynamic>{
      'p_pharmacy_id': pharmacyId,
      'p_medicine_id': medicineId,
      'p_price': price,
    });
    return J.str(J.map(r)['id']);
  }

  /// Any call confirms the row (`confirmed_at = now()`); null arguments stay unchanged.
  Future<void> updateProduct(String productId, {double? price, bool? isAvailable}) async {
    await _api.rpc('update_pharmacy_product', <String, dynamic>{
      'p_product_id': productId,
      'p_price': price,
      'p_is_available': isAvailable,
    });
  }

  /// "My list is still correct today": refreshes the confirmation time of every available product. Returns how many.
  Future<int> confirmListing(String pharmacyId) async {
    final dynamic r = await _api.rpc('confirm_listing', <String, dynamic>{'p_pharmacy_id': pharmacyId});
    return J.integer(J.map(r)['confirmed']);
  }

  /// Imports matched rows (existing rows get the new price and become available). Sent in chunks of [importChunk];
  /// [onProgress] receives (rows sent so far, total). A failing chunk throws after the earlier chunks were saved:
  /// importing is idempotent, so the same rows can simply be sent again.
  Future<ImportResult> bulkUpsert(String pharmacyId, List<ListingEntry> entries, {void Function(int done, int total)? onProgress}) async {
    ImportResult total = ImportResult.zero;
    for (int start = 0; start < entries.length; start += importChunk) {
      final int end = (start + importChunk) < entries.length ? start + importChunk : entries.length;
      final dynamic r = await _api.rpc('bulk_upsert_pharmacy_products', <String, dynamic>{
        'p_pharmacy_id': pharmacyId,
        'p_items': entries
            .sublist(start, end)
            .map((ListingEntry e) => <String, dynamic>{'medicine_id': e.medicineId, 'price': e.price})
            .toList(),
      });
      total = total + ImportResult.fromJson(r);
      onProgress?.call(end, entries.length);
    }
    return total;
  }

  /// Suggestions (up to three per name) from the shared catalogue for names read from a spreadsheet. The result list is
  /// aligned with [names]: element `i` holds the suggestions of `names[i]`, best first (empty = nothing close).
  Future<List<List<NameMatch>>> matchNames(List<String> names, {void Function(int done, int total)? onProgress}) async {
    final List<List<NameMatch>> out = List<List<NameMatch>>.generate(names.length, (int _) => <NameMatch>[]);
    for (int start = 0; start < names.length; start += matchChunk) {
      final int end = (start + matchChunk) < names.length ? start + matchChunk : names.length;
      final dynamic r = await _api.rpc('match_medicine_names', <String, dynamic>{'p_names': names.sublist(start, end)});
      for (final Map<String, dynamic> row in J.list(r)) {
        final NameMatch m = NameMatch.fromJson(row);
        final int global = start + m.index - 1;
        if (global >= start && global < end) out[global].add(m);
      }
      for (int i = start; i < end; i++) {
        out[i].sort((NameMatch a, NameMatch b) => b.score.compareTo(a.score));
      }
      onProgress?.call(end, names.length);
    }
    return out;
  }
}
