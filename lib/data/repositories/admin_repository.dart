import '../datasources/api_client.dart';
import '../models/json_utils.dart';
import '../models/platform.dart';

/// Admin-only reads and actions that are not about pharmacies or the medicine catalogue.
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  Future<AdminMetrics> metrics() async => AdminMetrics.fromJson(J.map(await _api.rpc('admin_metrics')));

  /// Reports, newest first. [statuses] limits the list (`open`, `in_review`, `resolved`, `dismissed`); null = all.
  Future<List<UserReport>> reports({List<String>? statuses, int limit = 30, int offset = 0}) async {
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'user_reports',
      inList: statuses == null ? const <String, List<Object>>{} : <String, List<Object>>{'status': statuses.cast<Object>()},
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    return rows.map(UserReport.fromJson).toList();
  }

  Future<UserReport?> report(String id) async {
    final Map<String, dynamic>? row = await _api.selectOne(Query('user_reports', eq: <String, Object>{'id': id}));
    return row == null ? null : UserReport.fromJson(row);
  }

  /// `status`: in_review | resolved | dismissed.
  Future<void> resolveReport(String id, String status, {String? note}) async {
    await _api.rpc('admin_resolve_report', <String, dynamic>{
      'p_report_id': id,
      'p_status': status,
      'p_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    });
  }

  /// Pharmacist and admin accounts (customers are never listed here). [role] narrows to `pharmacist` or `admin`.
  Future<List<AccountSummary>> accounts({String? text, String? role, int limit = 30, int offset = 0}) async {
    final String t = (text ?? '').trim().replaceAll(RegExp(r'[,()*%]'), ' ').trim();
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'profiles',
      eq: role == null ? const <String, Object>{} : <String, Object>{'role': role},
      inList: role != null
          ? const <String, List<Object>>{}
          : const <String, List<Object>>{
              'role': <Object>['pharmacist', 'admin'],
            },
      orFilter: t.isEmpty ? null : 'display_name.ilike.*$t*,phone.ilike.*$t*',
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    return rows.map(AccountSummary.fromJson).toList();
  }

  Future<void> setAccountStatus(String userId, {required bool suspended, String? reason}) async {
    await _api.rpc('admin_set_account_status', <String, dynamic>{
      'p_user_id': userId,
      'p_status': suspended ? 'suspended' : 'active',
      'p_reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
    });
  }

  /// Audit entries, newest first. [actions] limits the list to those action names; null = every action.
  Future<List<AuditLogEntry>> auditLog({List<String>? actions, int limit = 40, int offset = 0}) async {
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'audit_logs',
      inList: actions == null ? const <String, List<Object>>{} : <String, List<Object>>{'action': actions.cast<Object>()},
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    return rows.map(AuditLogEntry.fromJson).toList();
  }

  /// Display names of [ids] (admins may read non-customer profiles only, so customers are simply missing).
  Future<Map<String, String>> names(Iterable<String> ids) async {
    final List<Object> unique = ids.where((String i) => i.isNotEmpty).toSet().cast<Object>().toList();
    if (unique.isEmpty) return <String, String>{};
    final List<Map<String, dynamic>> rows = await _api.select(Query('profiles', columns: 'id,display_name', inList: <String, List<Object>>{'id': unique}));
    return <String, String>{for (final Map<String, dynamic> r in rows) J.str(r['id']): J.str(r['display_name'])};
  }
}
