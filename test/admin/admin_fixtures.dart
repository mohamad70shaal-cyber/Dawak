// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/features/admin/services/admin_dialog_hooks.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';

/// Signs in the administrator `admin-1` and loads the session.
Future<void> signInAdmin(AppHarness h) async {
  h.signInAs('admin-1', role: 'admin');
  await h.session.restore();
}

AdminConfirmFn answer(bool yes) =>
    ({required String title, required String message, String? confirmLabel, bool destructive = false}) async => yes;

AdminReasonFn reasonIs(String? reason) => ({
      required String title,
      required String label,
      String? message,
      String? confirmLabel,
      int minLength = 3,
      bool destructive = true,
    }) async =>
        reason;

/// Adds an account row besides the administrator's own.
void addProfile(AppHarness h, String id, {String role = 'pharmacist', String status = 'active', String name = 'صيدلاني', String? phone, String? reason}) {
  (h.api.tables['profiles'] ??= <Map<String, dynamic>>[]).add(<String, dynamic>{
    ...Fx.profileRow(id, role: role, status: status, name: name, reason: reason),
    'phone': phone,
  });
}

/// A pharmacy row as the admin list reads it.
Map<String, dynamic> pharmacy(
  String id, {
  String status = 'pending',
  String owner = 'owner-1',
  String name = 'صيدلية الشفاء',
  String? license = 'owner-1/license.pdf',
  String? reason,
  String submittedAt = '2026-10-10T10:00:00Z',
}) =>
    <String, dynamic>{
      ...Fx.pharmacyRow(id, owner: owner, status: status, name: name),
      'license_document_path': license,
      'status_reason': reason,
      'submitted_at': submittedAt,
    };

void seedPharmacies(AppHarness h, List<Map<String, dynamic>> rows) => h.api.tables['pharmacies'] = rows;

/// `admin_review_pharmacy` as the database does it: the allowed transitions, the reason rule and the new row.
void pharmacyReviewRpc(AppHarness h) {
  h.api.rpcs['admin_review_pharmacy'] = (Map<String, dynamic> p) {
    final Map<String, dynamic> row = h.api.tables['pharmacies']!.firstWhere((Map<String, dynamic> r) => r['id'] == p['p_pharmacy_id']);
    final String from = row['approval_status'] as String;
    final String reason = ((p['p_reason'] as String?) ?? '').trim();
    final String decision = p['p_decision'] as String;
    const Map<String, ({String from, String to, bool needsReason})> rules = <String, ({String from, String to, bool needsReason})>{
      'approve': (from: 'pending', to: 'approved', needsReason: false),
      'reject': (from: 'pending', to: 'rejected', needsReason: true),
      'suspend': (from: 'approved', to: 'suspended', needsReason: true),
      'reinstate': (from: 'suspended', to: 'approved', needsReason: false),
    };
    final ({String from, String to, bool needsReason})? rule = rules[decision];
    if (rule == null) throw const AppFailure('invalid_input');
    if (from != rule.from) throw const AppFailure('invalid_transition');
    if (rule.needsReason && reason.isEmpty) throw const AppFailure('invalid_input');
    row['approval_status'] = rule.to;
    row['status_reason'] = rule.needsReason ? reason : null;
    row['is_listed'] = rule.to == 'approved';
    return Map<String, dynamic>.from(row);
  };
}

Map<String, dynamic> medicine(String id, {String status = 'approved', String ar = 'بنادول', String en = 'Panadol', String? category, String createdAt = '2026-10-01T10:00:00Z'}) =>
    <String, dynamic>{
      ...Fx.medicineRow(id, ar: ar, en: en),
      'catalog_status': status,
      'category_id': category,
      'created_at': createdAt,
    };

void seedMedicines(AppHarness h, List<Map<String, dynamic>> rows) => h.api.tables['medicines'] = rows;

/// `admin_review_medicine` with the database's transition rules.
void medicineReviewRpc(AppHarness h) {
  h.api.rpcs['admin_review_medicine'] = (Map<String, dynamic> p) {
    final Map<String, dynamic> row = h.api.tables['medicines']!.firstWhere((Map<String, dynamic> r) => r['id'] == p['p_medicine_id']);
    final String from = row['catalog_status'] as String;
    switch (p['p_decision']) {
      case 'approve':
        if (from != 'pending') throw const AppFailure('invalid_transition');
        row['catalog_status'] = 'approved';
      case 'reject':
        if (from != 'pending') throw const AppFailure('invalid_transition');
        row['catalog_status'] = 'rejected';
      case 'archive':
        if (from == 'archived') throw const AppFailure('invalid_transition');
        row['catalog_status'] = 'archived';
      default:
        throw const AppFailure('invalid_input');
    }
    return <String, dynamic>{'id': row['id'], 'catalog_status': row['catalog_status']};
  };
}

Map<String, dynamic> report(
  String id, {
  String status = 'open',
  String target = 'pharmacy',
  String? targetId = 'ph-1',
  String category = 'pharmacy_problem',
  String description = 'الصيدلية لا ترد على الهاتف',
  String createdAt = '2026-10-12T10:00:00Z',
  String? note,
}) =>
    <String, dynamic>{
      'id': id,
      'reporter_id': 'c1',
      'target_type': target,
      'target_id': targetId,
      'category': category,
      'description': description,
      'status': status,
      'resolution_note': note,
      'created_at': createdAt,
    };

/// `admin_resolve_report`: stores the status and the (blank-as-null) note.
void reportRpc(AppHarness h) {
  h.api.rpcs['admin_resolve_report'] = (Map<String, dynamic> p) {
    final Map<String, dynamic> row = h.api.tables['user_reports']!.firstWhere((Map<String, dynamic> r) => r['id'] == p['p_report_id']);
    row['status'] = p['p_status'];
    row['resolution_note'] = p['p_note'];
    return <String, dynamic>{'id': row['id'], 'status': row['status']};
  };
}
