import 'json_utils.dart';

class SaleItem {
  const SaleItem({
    required this.lineNo,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.strength,
  });

  final int lineNo;
  final String productId;
  final String name;
  final String? strength;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  factory SaleItem.fromJson(Map<String, dynamic> j) => SaleItem(
        lineNo: J.integer(j['line_no']),
        productId: J.str(j['product_id']),
        name: J.str(j['name'] ?? j['product_name']),
        strength: J.strOrNull(j['strength']),
        quantity: J.integer(j['quantity']),
        unitPrice: J.number(j['unit_price']),
        lineTotal: J.number(j['line_total']),
      );
}

/// A completed cash sale (POS or order handover). Receipts are rendered from this.
class Sale {
  const Sale({
    required this.id,
    required this.invoiceNo,
    required this.currency,
    required this.subtotal,
    required this.discountAmount,
    required this.total,
    required this.createdAt,
    required this.items,
    this.orderId,
    this.cashierName = '',
    this.pharmacyName = '',
    this.pharmacyPhone,
    this.pharmacyAddress = '',
  });

  final String id;
  final String invoiceNo;
  final String? orderId;
  final String currency;
  final double subtotal;
  final double discountAmount;
  final double total;
  final DateTime? createdAt;
  final List<SaleItem> items;
  final String cashierName;
  final String pharmacyName;
  final String? pharmacyPhone;
  final String pharmacyAddress;

  bool get hasDiscount => discountAmount > 0;

  bool get isFromOrder => orderId != null;

  /// From the `get_sale` / `create_pos_sale` / `complete_order` JSON.
  factory Sale.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> ph = J.map(j['pharmacy']);
    final List<SaleItem> items = J.list(j['items']).map(SaleItem.fromJson).toList()
      ..sort((SaleItem a, SaleItem b) => a.lineNo.compareTo(b.lineNo));
    return Sale(
      id: J.str(j['id']),
      invoiceNo: J.str(j['invoice_no']),
      orderId: J.strOrNull(j['order_id']),
      currency: J.str(j['currency'], 'SYP'),
      subtotal: J.number(j['subtotal']),
      discountAmount: J.number(j['discount_amount']),
      total: J.number(j['total']),
      createdAt: J.date(j['created_at']),
      items: items,
      cashierName: J.str(j['cashier_name']),
      pharmacyName: J.str(ph['name']),
      pharmacyPhone: J.strOrNull(ph['phone']),
      pharmacyAddress: <String>[J.str(ph['address_line']), J.str(ph['neighborhood']), J.str(ph['city'])]
          .where((String s) => s.trim().isNotEmpty)
          .join('، '),
    );
  }
}

/// A row of the sales history list (`sales` table, no items).
class SaleSummary {
  const SaleSummary({
    required this.id,
    required this.invoiceNo,
    required this.currency,
    required this.total,
    required this.discountAmount,
    required this.createdAt,
    this.orderId,
  });

  final String id;
  final String invoiceNo;
  final String currency;
  final double total;
  final double discountAmount;
  final DateTime? createdAt;
  final String? orderId;

  factory SaleSummary.fromJson(Map<String, dynamic> j) => SaleSummary(
        id: J.str(j['id']),
        invoiceNo: J.str(j['invoice_no']),
        currency: J.str(j['currency'], 'SYP'),
        total: J.number(j['total']),
        discountAmount: J.number(j['discount_amount']),
        createdAt: J.date(j['created_at']),
        orderId: J.strOrNull(j['order_id']),
      );
}
