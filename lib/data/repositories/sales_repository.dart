import '../../core/utils/idempotency.dart';
import '../datasources/api_client.dart';
import '../models/json_utils.dart';
import '../models/order.dart';
import '../models/sale.dart';

class SalesRepository {
  SalesRepository(this._api);

  final ApiClient _api;

  /// Creates a cash sale. The server always prices the lines from the pharmacy's list and does **not** compare the price the cashier saw
  /// (`expectedUnitPrice` is sent but ignored by `create_pos_sale`), so the receipt may differ from the basket if a price changed meanwhile.
  /// Pass the same [idempotencyKey] when retrying the same cart so a lost response never produces a second sale.
  Future<Sale> createPosSale({
    required String pharmacyId,
    required List<OrderLineInput> items,
    required double discount,
    required String idempotencyKey,
  }) async {
    final dynamic r = await _api.rpc('create_pos_sale', <String, dynamic>{
      'p_pharmacy_id': pharmacyId,
      'p_items': items.map((OrderLineInput l) => l.toJson()).toList(),
      'p_discount': discount,
      'p_idempotency_key': idempotencyKey,
    });
    return Sale.fromJson(J.map(r));
  }

  Future<Sale> getSale(String saleId) async {
    final dynamic r = await _api.rpc('get_sale', <String, dynamic>{'p_sale_id': saleId});
    return Sale.fromJson(J.map(r));
  }

  /// Sales history. Cashiers only see their own (RLS), owners/managers see all.
  Future<List<SaleSummary>> history(
    String pharmacyId, {
    DateTime? from,
    DateTime? to,
    String? invoiceQuery,
    int limit = 30,
    int offset = 0,
  }) async {
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'sales',
      eq: <String, Object>{'pharmacy_id': pharmacyId},
      gte: <String, Object>{if (from != null) 'created_at': from.toUtc().toIso8601String()},
      lt: <String, Object>{if (to != null) 'created_at': to.toUtc().toIso8601String()},
      orFilter: _invoiceFilter(invoiceQuery),
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    return rows.map(SaleSummary.fromJson).toList();
  }

  static String? _invoiceFilter(String? q) {
    final String t = (q ?? '').trim().replaceAll(RegExp(r'[,()*%]'), '');
    return t.isEmpty ? null : 'invoice_no.ilike.*$t*';
  }

  /// A fresh key for one cart; keep it until the cart changes.
  String newKey() => newIdempotencyKey();
}
