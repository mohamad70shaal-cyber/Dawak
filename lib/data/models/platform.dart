import 'enums.dart';
import 'json_utils.dart';
import 'pharmacy.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.params,
    required this.createdAt,
    this.entityType,
    this.entityId,
    this.readAt,
  });

  final String id;

  /// e.g. `order_accepted`, `order_new`, `pharmacy_approved` (translated through `notif_<kind>`).
  final String kind;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic> params;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isUnread => readAt == null;

  String get ref => J.str(params['ref']);

  /// Medicine / pharmacy names carried by the `availability_*` notifications.
  String get medicine => J.str(params['medicine']);

  String get pharmacy => J.str(params['pharmacy']);

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: J.str(j['id']),
        kind: J.str(j['kind']),
        entityType: J.strOrNull(j['entity_type']),
        entityId: J.strOrNull(j['entity_id']),
        params: J.map(j['params']),
        readAt: J.date(j['read_at']),
        createdAt: J.date(j['created_at']),
      );
}

class UserReport {
  const UserReport({
    required this.id,
    required this.reporterId,
    required this.targetType,
    required this.category,
    required this.description,
    required this.status,
    required this.createdAt,
    this.targetId,
    this.resolutionNote,
  });

  final String id;
  final String reporterId;

  /// `pharmacy`, `medicine`, `order`, `app` or `other`.
  final String targetType;
  final String? targetId;
  final String category;
  final String description;

  /// `open`, `in_review`, `resolved`, `dismissed`.
  final String status;
  final String? resolutionNote;
  final DateTime? createdAt;

  bool get isOpen => status == 'open' || status == 'in_review';

  factory UserReport.fromJson(Map<String, dynamic> j) => UserReport(
        id: J.str(j['id']),
        reporterId: J.str(j['reporter_id']),
        targetType: J.str(j['target_type'], 'other'),
        targetId: J.strOrNull(j['target_id']),
        category: J.str(j['category']),
        description: J.str(j['description']),
        status: J.str(j['status'], 'open'),
        resolutionNote: J.strOrNull(j['resolution_note']),
        createdAt: J.date(j['created_at']),
      );
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.details,
    required this.createdAt,
    this.actorId,
    this.entityId,
    this.pharmacyId,
  });

  final String id;
  final String? actorId;
  final String action;
  final String entityType;
  final String? entityId;
  final String? pharmacyId;
  final Map<String, dynamic> details;
  final DateTime? createdAt;

  factory AuditLogEntry.fromJson(Map<String, dynamic> j) => AuditLogEntry(
        id: J.str(j['id']),
        actorId: J.strOrNull(j['actor_id']),
        action: J.str(j['action']),
        entityType: J.str(j['entity_type']),
        entityId: J.strOrNull(j['entity_id']),
        pharmacyId: J.strOrNull(j['pharmacy_id']),
        details: J.map(j['details']),
        createdAt: J.date(j['created_at']),
      );
}

/// A pharmacist/admin account row for the admin "accounts" screen (customers are never listed).
class AccountSummary {
  const AccountSummary({
    required this.id,
    required this.role,
    required this.suspended,
    required this.displayName,
    this.phone,
    this.suspendedReason,
    this.createdAt,
  });

  final String id;
  final UserRole role;
  final bool suspended;
  final String displayName;
  final String? phone;
  final String? suspendedReason;
  final DateTime? createdAt;

  factory AccountSummary.fromJson(Map<String, dynamic> j) => AccountSummary(
        id: J.str(j['id']),
        role: UserRole.parse(J.strOrNull(j['role'])),
        suspended: J.str(j['account_status']) == 'suspended',
        displayName: J.str(j['display_name']),
        phone: J.strOrNull(j['phone']),
        suspendedReason: J.strOrNull(j['suspended_reason']),
        createdAt: J.date(j['created_at']),
      );
}

/// A pharmacy application as listed for admins (pharmacy row plus its owner's name).
class PharmacyApplication {
  const PharmacyApplication({required this.pharmacy, required this.ownerName, this.ownerPhone});

  final Pharmacy pharmacy;
  final String ownerName;
  final String? ownerPhone;
}

class AdminMetrics {
  const AdminMetrics({
    required this.pendingPharmacies,
    required this.approvedPharmacies,
    required this.rejectedPharmacies,
    required this.suspendedPharmacies,
    required this.customers,
    required this.pharmacists,
    required this.suspendedUsers,
    required this.approvedMedicines,
    required this.pendingMedicines,
    required this.orders30d,
    required this.completedOrders30d,
    required this.cancelledOrRejected30d,
    required this.sales30d,
    required this.openReports,
  });

  final int pendingPharmacies;
  final int approvedPharmacies;
  final int rejectedPharmacies;
  final int suspendedPharmacies;
  final int customers;
  final int pharmacists;
  final int suspendedUsers;
  final int approvedMedicines;
  final int pendingMedicines;
  final int orders30d;
  final int completedOrders30d;
  final int cancelledOrRejected30d;
  final int sales30d;
  final int openReports;

  factory AdminMetrics.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> ph = J.map(j['pharmacies']);
    final Map<String, dynamic> us = J.map(j['users']);
    final Map<String, dynamic> me = J.map(j['medicines']);
    final Map<String, dynamic> or = J.map(j['orders_30d']);
    return AdminMetrics(
      pendingPharmacies: J.integer(ph['pending']),
      approvedPharmacies: J.integer(ph['approved']),
      rejectedPharmacies: J.integer(ph['rejected']),
      suspendedPharmacies: J.integer(ph['suspended']),
      customers: J.integer(us['customers']),
      pharmacists: J.integer(us['pharmacists']),
      suspendedUsers: J.integer(us['suspended']),
      approvedMedicines: J.integer(me['approved']),
      pendingMedicines: J.integer(me['pending']),
      orders30d: J.integer(or['total']),
      completedOrders30d: J.integer(or['completed']),
      cancelledOrRejected30d: J.integer(or['cancelled_or_rejected']),
      sales30d: J.integer(j['sales_30d_count']),
      openReports: J.integer(j['open_reports']),
    );
  }
}
