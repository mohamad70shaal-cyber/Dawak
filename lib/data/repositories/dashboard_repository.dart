import '../datasources/api_client.dart';
import '../models/dashboard.dart';
import '../models/json_utils.dart';

class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  /// Owner/manager figures. Dates are calendar days in the pharmacy's time zone (server side).
  Future<DashboardData> load(String pharmacyId, {DateTime? from, DateTime? to}) async {
    final dynamic r = await _api.rpc('pharmacy_dashboard', <String, dynamic>{
      'p_pharmacy_id': pharmacyId,
      'p_from': from == null ? null : _day(from),
      'p_to': to == null ? null : _day(to),
    });
    return DashboardData.fromJson(J.map(r));
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
