import 'enums.dart';
import 'json_utils.dart';

class PeriodTotal {
  const PeriodTotal({required this.total, required this.count});

  final double total;
  final int count;

  static const PeriodTotal zero = PeriodTotal(total: 0, count: 0);

  factory PeriodTotal.fromJson(Object? raw) {
    final Map<String, dynamic> j = J.map(raw);
    return PeriodTotal(total: J.number(j['total']), count: J.integer(j['count']));
  }
}

class DailyPoint {
  const DailyPoint({required this.day, required this.total, required this.count});

  final DateTime day;
  final double total;
  final int count;

  factory DailyPoint.fromJson(Map<String, dynamic> j) => DailyPoint(
        day: J.date(j['day']) ?? DateTime.now(),
        total: J.number(j['total']),
        count: J.integer(j['count']),
      );
}

class BestSeller {
  const BestSeller({required this.productId, required this.name, required this.quantity, required this.revenue});

  final String productId;
  final String name;
  final int quantity;
  final double revenue;

  factory BestSeller.fromJson(Map<String, dynamic> j) => BestSeller(
        productId: J.str(j['product_id']),
        name: J.str(j['name']),
        quantity: J.integer(j['quantity']),
        revenue: J.number(j['revenue']),
      );
}

/// Summary of the pharmacy's list (no quantities): how many products are marked available / unavailable and
/// how many available ones have not been confirmed for a week.
class ListingSummary {
  const ListingSummary({required this.available, required this.unavailable, required this.stale});

  final int available;
  final int unavailable;
  final int stale;

  static const ListingSummary empty = ListingSummary(available: 0, unavailable: 0, stale: 0);

  int get total => available + unavailable;

  factory ListingSummary.fromJson(Object? raw) {
    final Map<String, dynamic> j = J.map(raw);
    return ListingSummary(available: J.integer(j['available']), unavailable: J.integer(j['unavailable']), stale: J.integer(j['stale']));
  }
}

class RecentOrder {
  const RecentOrder({
    required this.id,
    required this.publicRef,
    required this.status,
    required this.subtotal,
    required this.currency,
    required this.createdAt,
    required this.customerName,
  });

  final String id;
  final String publicRef;
  final OrderStatus status;
  final double subtotal;
  final String currency;
  final DateTime? createdAt;
  final String customerName;

  factory RecentOrder.fromJson(Map<String, dynamic> j) => RecentOrder(
        id: J.str(j['id']),
        publicRef: J.str(j['public_ref']),
        status: OrderStatus.parse(J.strOrNull(j['status'])),
        subtotal: J.number(j['subtotal']),
        currency: J.str(j['currency'], 'SYP'),
        createdAt: J.date(j['created_at']),
        customerName: J.str(j['customer_name']),
      );
}

/// Result of `pharmacy_dashboard`. Figures come only from completed sales.
class DashboardData {
  const DashboardData({
    required this.currency,
    required this.today,
    required this.week,
    required this.last10Days,
    required this.month,
    required this.range,
    required this.rangeFrom,
    required this.rangeTo,
    required this.dailySeries,
    required this.bestSellers,
    required this.listing,
    required this.openRequestsCount,
    required this.pendingOrdersCount,
    required this.recentOrders,
  });

  final String currency;
  final PeriodTotal today;
  final PeriodTotal week;
  final PeriodTotal last10Days;
  final PeriodTotal month;
  final PeriodTotal range;
  final DateTime? rangeFrom;
  final DateTime? rangeTo;
  final List<DailyPoint> dailySeries;
  final List<BestSeller> bestSellers;
  final ListingSummary listing;

  /// Availability requests from customers that this pharmacy has not answered yet.
  final int openRequestsCount;
  final int pendingOrdersCount;
  final List<RecentOrder> recentOrders;

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> range = J.map(j['range']);
    return DashboardData(
      currency: J.str(j['currency'], 'SYP'),
      today: PeriodTotal.fromJson(j['today']),
      week: PeriodTotal.fromJson(j['week']),
      last10Days: PeriodTotal.fromJson(j['last_10_days']),
      month: PeriodTotal.fromJson(j['month']),
      range: PeriodTotal.fromJson(range),
      rangeFrom: J.date(range['from']),
      rangeTo: J.date(range['to']),
      dailySeries: J.list(j['daily_series']).map(DailyPoint.fromJson).toList(),
      bestSellers: J.list(j['best_sellers']).map(BestSeller.fromJson).toList(),
      listing: ListingSummary.fromJson(j['listing']),
      openRequestsCount: J.integer(j['open_requests_count']),
      pendingOrdersCount: J.integer(j['pending_orders_count']),
      recentOrders: J.list(j['recent_orders']).map(RecentOrder.fromJson).toList(),
    );
  }
}
