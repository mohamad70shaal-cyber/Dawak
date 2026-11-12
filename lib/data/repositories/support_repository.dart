import '../datasources/api_client.dart';
import '../models/platform.dart';

/// User-submitted reports (problem with a pharmacy, a medicine entry, an order or the app).
class SupportRepository {
  SupportRepository(this._api);

  final ApiClient _api;

  static const List<String> targetTypes = <String>['pharmacy', 'medicine', 'order', 'app', 'other'];

  Future<void> submitReport({
    required String targetType,
    String? targetId,
    required String category,
    required String description,
  }) async {
    await _api.insertOnly('user_reports', <String, dynamic>{
      'target_type': targetType,
      if (targetId != null) 'target_id': targetId,
      'category': category.trim(),
      'description': description.trim(),
    });
  }

  Future<List<UserReport>> myReports({int limit = 30, int offset = 0}) async {
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'user_reports',
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    return rows.map(UserReport.fromJson).toList();
  }
}
