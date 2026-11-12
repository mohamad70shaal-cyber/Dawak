import '../datasources/api_client.dart';
import '../models/platform.dart';

class NotificationRepository {
  NotificationRepository(this._api);

  final ApiClient _api;

  Future<List<AppNotification>> list({int limit = 30, int offset = 0}) async {
    final List<Map<String, dynamic>> rows = await _api.select(Query(
      'notifications',
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
      offset: offset,
    ));
    return rows.map(AppNotification.fromJson).toList();
  }

  Future<int> unreadCount() async {
    final List<Map<String, dynamic>> rows = await _api.select(const Query(
      'notifications',
      columns: 'id',
      isNull: <String>['read_at'],
      limit: 100,
    ));
    return rows.length;
  }

  Future<void> markRead(String id) async {
    await _api.update('notifications', <String, dynamic>{'read_at': DateTime.now().toUtc().toIso8601String()},
        eq: <String, Object>{'id': id});
  }
}
