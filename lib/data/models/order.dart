import 'enums.dart';
import 'json_utils.dart';

class OrderItem {
  const OrderItem({
    required this.id,
    required this.lineNo,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.strength,
    this.dosageForm,
  });

  final String id;
  final int lineNo;
  final String productId;
  final String name;
  final String? strength;
  final String? dosageForm;
  final int quantity;
  final double unitPrice;

  double get lineTotal => ((unitPrice * quantity) * 100).round() / 100;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        id: J.str(j['id']),
        lineNo: J.integer(j['line_no']),
        productId: J.str(j['product_id']),
        name: J.str(j['medicine_name']),
        strength: J.strOrNull(j['strength']),
        dosageForm: J.strOrNull(j['dosage_form']),
        quantity: J.integer(j['quantity']),
        unitPrice: J.number(j['unit_price']),
      );
}

/// A reservation order, seen by the customer or by the pharmacy (same row, different screens).
class Order {
  const Order({
    required this.id,
    required this.publicRef,
    required this.customerId,
    required this.pharmacyId,
    required this.status,
    required this.currency,
    required this.subtotal,
    required this.items,
    required this.createdAt,
    this.pharmacyName = '',
    this.pharmacyAddress,
    this.pharmacyPhone,
    this.customerName = '',
    this.contactPhone,
    this.customerNotes,
    this.rejectReason,
    this.cancelReason,
    this.cancelledByRole,
    this.acceptedAt,
    this.readyAt,
    this.completedAt,
    this.rejectedAt,
    this.cancelledAt,
    this.expiredAt,
    this.reservationExpiresAt,
  });

  final String id;

  /// Short code the customer shows at the counter (`DWK-XXXXXXXXXX`).
  final String publicRef;
  final String customerId;
  final String pharmacyId;
  final OrderStatus status;
  final String currency;
  final double subtotal;
  final List<OrderItem> items;
  final DateTime? createdAt;

  /// Snapshot of the pharmacy at order time (customers cannot read the pharmacies table).
  final String pharmacyName;
  final String? pharmacyAddress;
  final String? pharmacyPhone;

  final String customerName;
  final String? contactPhone;
  final String? customerNotes;
  final String? rejectReason;
  final String? cancelReason;

  /// `customer` or `pharmacy`.
  final String? cancelledByRole;
  final DateTime? acceptedAt;
  final DateTime? readyAt;
  final DateTime? completedAt;
  final DateTime? rejectedAt;
  final DateTime? cancelledAt;
  final DateTime? expiredAt;
  final DateTime? reservationExpiresAt;

  int get itemCount => items.fold<int>(0, (int s, OrderItem i) => s + i.quantity);

  /// Time left on the promise to hold the medicine (null when the order is not accepted / ready).
  Duration? remaining({DateTime? now}) {
    final DateTime? end = reservationExpiresAt;
    if (end == null || !status.isPromised) return null;
    return end.difference(now ?? DateTime.now());
  }

  bool get customerCanCancel =>
      status == OrderStatus.pending ||
      status == OrderStatus.accepted ||
      status == OrderStatus.readyForPickup ||
      status == OrderStatus.expired;

  /// `order_items(*)` is the embedded relation of the select; RPC results use the `items` key.
  factory Order.fromJson(Map<String, dynamic> j) {
    final List<Map<String, dynamic>> rawItems = J.list(j['order_items'] ?? j['items']);
    final List<OrderItem> items = rawItems.map(OrderItem.fromJson).toList()
      ..sort((OrderItem a, OrderItem b) => a.lineNo.compareTo(b.lineNo));
    return Order(
      id: J.str(j['id']),
      publicRef: J.str(j['public_ref']),
      customerId: J.str(j['customer_id']),
      pharmacyId: J.str(j['pharmacy_id']),
      status: OrderStatus.parse(J.strOrNull(j['status'])),
      currency: J.str(j['currency'], 'SYP'),
      subtotal: J.number(j['subtotal']),
      items: items,
      createdAt: J.date(j['created_at']),
      pharmacyName: J.str(j['pharmacy_name']),
      pharmacyAddress: J.strOrNull(j['pharmacy_address']),
      pharmacyPhone: J.strOrNull(j['pharmacy_phone']),
      customerName: J.str(j['customer_name']),
      contactPhone: J.strOrNull(j['contact_phone']),
      customerNotes: J.strOrNull(j['customer_notes']),
      rejectReason: J.strOrNull(j['reject_reason']),
      cancelReason: J.strOrNull(j['cancel_reason']),
      cancelledByRole: J.strOrNull(j['cancelled_by_role']),
      acceptedAt: J.date(j['accepted_at']),
      readyAt: J.date(j['ready_at']),
      completedAt: J.date(j['completed_at']),
      rejectedAt: J.date(j['rejected_at']),
      cancelledAt: J.date(j['cancelled_at']),
      expiredAt: J.date(j['expired_at']),
      reservationExpiresAt: J.date(j['reservation_expires_at']),
    );
  }
}

/// A line the customer wants to reserve (before the server confirms).
class OrderLineInput {
  const OrderLineInput({required this.productId, required this.quantity, this.expectedUnitPrice});

  final String productId;
  final int quantity;

  /// The price the customer saw; the server answers `price_changed` if it differs.
  final double? expectedUnitPrice;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'product_id': productId,
        'quantity': quantity,
        if (expectedUnitPrice != null) 'expected_unit_price': expectedUnitPrice,
      };
}
