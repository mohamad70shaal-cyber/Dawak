import '../../core/errors/app_failure.dart';
import '../../core/utils/phone_utils.dart';
import '../datasources/api_client.dart';
import '../models/enums.dart';
import '../models/json_utils.dart';
import '../models/order.dart';
import '../models/sale.dart';

/// Reservation orders for both sides: the customer's own orders and the pharmacy's incoming ones.
class OrderRepository {
  OrderRepository(this._api);

  final ApiClient _api;

  static const String _columns = '*, order_items(*)';

  // ---- customer ------------------------------------------------------------------------------------------

  Future<Order> create({
    required String pharmacyId,
    required List<OrderLineInput> items,
    required String idempotencyKey,
    String? notes,
    String? contactPhone,
  }) async {
    final dynamic r = await _api.rpc('create_order', <String, dynamic>{
      'p_pharmacy_id': pharmacyId,
      'p_items': items.map((OrderLineInput l) => l.toJson()).toList(),
      'p_notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      'p_contact_phone': cleanPhone(contactPhone),
      'p_idempotency_key': idempotencyKey,
    });
    return Order.fromJson(J.map(r));
  }

  /// The customer's own orders, newest first. [activeOnly] = pending/accepted/ready.
  Future<List<Order>> myOrders({bool activeOnly = false, int limit = 20, int offset = 0}) async {
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'orders',
      columns: _columns,
      inList: activeOnly
          ? <String, List<Object>>{
              'status': <Object>['pending', 'accepted', 'ready_for_pickup'],
            }
          : const <String, List<Object>>{},
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    return rows.map(Order.fromJson).toList();
  }

  Future<Order?> getOrder(String id) async {
    final Map<String, dynamic>? row = await _api.selectOne(Query('orders', columns: _columns, eq: <String, Object>{'id': id}));
    return row == null ? null : Order.fromJson(row);
  }

  Future<Order> cancelByCustomer(String orderId, {String? reason}) async {
    final dynamic r = await _api.rpc('cancel_order', <String, dynamic>{
      'p_order_id': orderId,
      'p_reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
    });
    return Order.fromJson(J.map(r));
  }

  // ---- pharmacy ------------------------------------------------------------------------------------------

  /// Orders of the pharmacy, optionally only some statuses.
  Future<List<Order>> pharmacyOrders(
    String pharmacyId, {
    List<OrderStatus>? statuses,
    int limit = 20,
    int offset = 0,
  }) async {
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'orders',
      columns: _columns,
      eq: <String, Object>{'pharmacy_id': pharmacyId},
      inList: statuses == null || statuses.isEmpty
          ? const <String, List<Object>>{}
          : <String, List<Object>>{'status': statuses.map<Object>((OrderStatus s) => s.wire).toList()},
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    return rows.map(Order.fromJson).toList();
  }

  /// Sweeps expired reservations of this pharmacy so the list reflects reality (idempotent).
  Future<int> expireReservations(String pharmacyId) async {
    final dynamic r = await _api.rpc('expire_reservations', <String, dynamic>{'p_pharmacy_id': pharmacyId});
    return J.integer(J.map(r)['expired']);
  }

  Future<Order> accept(String orderId) async =>
      Order.fromJson(J.map(await _api.rpc('accept_order', <String, dynamic>{'p_order_id': orderId})));

  Future<Order> reject(String orderId, String reason) async => Order.fromJson(
      J.map(await _api.rpc('reject_order', <String, dynamic>{'p_order_id': orderId, 'p_reason': reason.trim()})));

  /// Pharmacy re-opens an expired reservation (the pharmacy promises to prepare it again for another 24 h).
  Future<Order> reactivate(String orderId) async =>
      Order.fromJson(J.map(await _api.rpc('reactivate_order', <String, dynamic>{'p_order_id': orderId})));

  Future<Order> markReady(String orderId) async =>
      Order.fromJson(J.map(await _api.rpc('mark_order_ready', <String, dynamic>{'p_order_id': orderId})));

  Future<Order> cancelByPharmacy(String orderId, String reason) async => Order.fromJson(
      J.map(await _api.rpc('pharmacy_cancel_order', <String, dynamic>{'p_order_id': orderId, 'p_reason': reason.trim()})));

  /// Hands the goods over against cash. [reference] is the code the customer shows (`DWK-…`); returns the sale.
  Future<Sale> complete(String orderId, String reference) async => Sale.fromJson(J.map(
      await _api.rpc('complete_order', <String, dynamic>{'p_order_id': orderId, 'p_reference': reference.trim()})));

  /// Looks an order up by the code a customer reads out. Returns null when there is no such order.
  Future<Order?> findByRef(String pharmacyId, String ref) async {
    try {
      final dynamic r = await _api.rpc('find_order_by_ref', <String, dynamic>{
        'p_pharmacy_id': pharmacyId,
        'p_ref': ref.trim().toUpperCase(),
      });
      return Order.fromJson(J.map(r));
    } on AppFailure catch (e) {
      if (e.code == 'not_found') return null;
      rethrow;
    }
  }
}
