import 'dart:async';

import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/core/services/location_service.dart';
import 'package:dawak/data/datasources/api_client.dart';
import 'package:dawak/data/models/geo.dart';

typedef RpcHandler = dynamic Function(Map<String, dynamic> params);

/// In-memory [ApiClient] for controller, repository and workflow tests.
///
/// - `tables` holds rows for `select` (filters, ordering and paging of [Query] are interpreted; embedded relations
///   such as `medicines(...)` must already be nested inside the rows).
/// - `rpcs` maps a function name to a handler returning the JSON result, or throwing [AppFailure].
/// - every call is recorded in [calls] (`rpc:<fn>`, `select:<table>`, `update:<table>`, `insert:<table>`).
/// - [failNext] makes the next call whose label starts with the prefix throw the given failure once.
class FakeApiClient implements ApiClient {
  final Map<String, List<Map<String, dynamic>>> tables = <String, List<Map<String, dynamic>>>{};
  final Map<String, RpcHandler> rpcs = <String, RpcHandler>{};
  final List<String> calls = <String>[];
  final List<({String fn, Map<String, dynamic> params})> rpcLog = <({String fn, Map<String, dynamic> params})>[];
  final Map<String, AppFailure> _fail = <String, AppFailure>{};

  /// Artificial latency for tests that need to observe in-flight state.
  Duration delay = Duration.zero;

  void failNext(String labelPrefix, AppFailure failure) => _fail[labelPrefix] = failure;

  Future<void> _enter(String label) async {
    calls.add(label);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final String? key = _fail.keys.cast<String?>().firstWhere((String? k) => label.startsWith(k!), orElse: () => null);
    if (key != null) throw _fail.remove(key)!;
  }

  int rpcCount(String fn) => rpcLog.where((e) => e.fn == fn).length;

  @override
  Future<dynamic> rpc(String fn, [Map<String, dynamic>? params]) async {
    await _enter('rpc:$fn');
    final Map<String, dynamic> p = params ?? <String, dynamic>{};
    rpcLog.add((fn: fn, params: p));
    final RpcHandler? h = rpcs[fn];
    if (h == null) throw StateError('FakeApiClient: no handler for rpc "$fn"');
    return h(p);
  }

  @override
  Future<List<Map<String, dynamic>>> select(Query q) async {
    await _enter('select:${q.table}');
    Iterable<Map<String, dynamic>> rows = (tables[q.table] ?? <Map<String, dynamic>>[]).map((Map<String, dynamic> r) => Map<String, dynamic>.from(r));
    bool same(Object? a, Object b) => a.toString() == b.toString();
    q.eq.forEach((String k, Object v) => rows = rows.where((Map<String, dynamic> r) => same(_at(r, k), v)));
    q.neq.forEach((String k, Object v) => rows = rows.where((Map<String, dynamic> r) => !same(_at(r, k), v)));
    q.inList.forEach((String k, List<Object> v) => rows = rows.where((Map<String, dynamic> r) => v.any((Object x) => same(_at(r, k), x))));
    int cmp(Object? a, Object b) {
      if (a == null) return -1;
      if (a is num && b is num) return a.compareTo(b);
      return a.toString().compareTo(b.toString());
    }

    q.gte.forEach((String k, Object v) => rows = rows.where((Map<String, dynamic> r) => cmp(_at(r, k), v) >= 0));
    q.lte.forEach((String k, Object v) => rows = rows.where((Map<String, dynamic> r) => cmp(_at(r, k), v) <= 0));
    q.lt.forEach((String k, Object v) => rows = rows.where((Map<String, dynamic> r) => cmp(_at(r, k), v) < 0));
    for (final String c in q.isNull) {
      rows = rows.where((Map<String, dynamic> r) => r[c] == null);
    }
    for (final String c in q.notNull) {
      rows = rows.where((Map<String, dynamic> r) => r[c] != null);
    }
    final String? or = q.orFilter;
    if (or != null) {
      final String? refTable = q.orReferencedTable;
      final List<({String col, String needle})> terms = or.split(',').map((String t) {
        final List<String> parts = t.split('.');
        return (col: parts.first, needle: parts.last.replaceAll('*', '').toLowerCase());
      }).toList();
      rows = rows.where((Map<String, dynamic> r) {
        final Map<String, dynamic> scope = refTable == null ? r : (r[refTable] is Map ? Map<String, dynamic>.from(r[refTable] as Map) : <String, dynamic>{});
        return terms.any((t) => (scope[t.col] ?? '').toString().toLowerCase().contains(t.needle));
      });
    }
    List<Map<String, dynamic>> list = rows.toList();
    final String? ob = q.orderBy;
    if (ob != null) {
      final String? ob2 = q.secondOrderBy;
      list.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        int c = _cmp(a[ob], b[ob]);
        if (!q.ascending) c = -c;
        if (c != 0 || ob2 == null) return c;
        final int c2 = _cmp(a[ob2], b[ob2]);
        return q.secondAscending ? c2 : -c2;
      });
    }
    final int off = q.offset ?? 0;
    if (off > 0) list = list.skip(off).toList();
    final int? lim = q.limit;
    if (lim != null) list = list.take(lim).toList();
    return list;
  }

  /// Column lookup that also follows `embedded.column` paths (PostgREST filters on embedded tables).
  static Object? _at(Map<String, dynamic> row, String key) {
    if (!key.contains('.')) return row[key];
    Object? cur = row;
    for (final String part in key.split('.')) {
      if (cur is Map) {
        cur = cur[part];
      } else {
        return null;
      }
    }
    return cur;
  }

  static int _cmp(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  @override
  Future<Map<String, dynamic>?> selectOne(Query q) async {
    final List<Map<String, dynamic>> rows = await select(q.copyWith(limit: 1));
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<int> update(String table, Map<String, dynamic> values, {required Map<String, Object> eq}) async {
    await _enter('update:$table');
    int n = 0;
    for (final Map<String, dynamic> r in tables[table] ?? <Map<String, dynamic>>[]) {
      if (eq.entries.every((MapEntry<String, Object> e) => r[e.key].toString() == e.value.toString())) {
        r.addAll(values);
        n++;
      }
    }
    return n;
  }

  @override
  Future<Map<String, dynamic>> insert(String table, Map<String, dynamic> values) async {
    await _enter('insert:$table');
    final Map<String, dynamic> row = <String, dynamic>{'id': 'gen-${(tables[table]?.length ?? 0) + 1}', ...values};
    (tables[table] ??= <Map<String, dynamic>>[]).add(row);
    return row;
  }

  @override
  Future<void> insertOnly(String table, Map<String, dynamic> values) async {
    await insert(table, values);
  }
}

/// Scriptable [AuthGateway]. Register accounts with [addUser]; `signIn` succeeds only for a matching pair.
class FakeAuthGateway implements AuthGateway {
  final StreamController<AuthEventKind> _events = StreamController<AuthEventKind>.broadcast();
  final Map<String, ({String id, String password})> users = <String, ({String id, String password})>{};
  String? _userId;
  String? _email;

  /// When false, `signUp` returns false (confirmation required) and does not open a session.
  bool confirmationsOff = false;
  final List<String> resetRequests = <String>[];
  final List<String> resendRequests = <String>[];
  AppFailure? nextFailure;

  void addUser(String email, String password, {String? id}) {
    users[email.toLowerCase()] = (id: id ?? 'user-${users.length + 1}', password: password);
  }

  /// Opens a session without a password (for tests that start signed in).
  void startSession(String id, String email) {
    _userId = id;
    _email = email;
  }

  void emit(AuthEventKind k) => _events.add(k);

  @override
  bool get hasSession => _userId != null;

  @override
  String? get currentUserId => _userId;

  @override
  String? get currentEmail => _email;

  @override
  Stream<AuthEventKind> get events => _events.stream;

  void _maybeFail() {
    final AppFailure? f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _maybeFail();
    final ({String id, String password})? u = users[email.trim().toLowerCase()];
    if (u == null || u.password != password) throw const AppFailure('invalid_credentials');
    _userId = u.id;
    _email = email.trim();
    _events.add(AuthEventKind.signedIn);
  }

  @override
  Future<bool> signUp({required String email, required String password, required String displayName}) async {
    _maybeFail();
    if (users.containsKey(email.trim().toLowerCase())) throw const AppFailure('email_taken');
    addUser(email, password);
    if (!confirmationsOff) return false;
    _userId = users[email.trim().toLowerCase()]!.id;
    _email = email.trim();
    return true;
  }

  @override
  Future<void> signOut() async {
    _userId = null;
    _email = null;
    _events.add(AuthEventKind.signedOut);
  }

  @override
  Future<void> resetPassword(String email) async {
    _maybeFail();
    resetRequests.add(email);
  }

  @override
  Future<void> resendConfirmation(String email) async {
    _maybeFail();
    resendRequests.add(email);
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    _maybeFail();
  }
}

class FakeFileStore implements FileStore {
  final List<String> uploaded = <String>[];
  AppFailure? nextFailure;

  @override
  Future<String> uploadLicense({required String userId, required String fileName, required List<int> bytes, required String contentType}) async {
    final AppFailure? f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
    final String path = '$userId/$fileName';
    uploaded.add(path);
    return path;
  }

  @override
  Future<String> signedLicenseUrl(String path, {Duration expiresIn = const Duration(minutes: 10)}) async => 'https://files.test/$path';
}

/// Scripted GPS for tests: returns [position] or throws [failure] (an [AppFailure] such as `location_denied`).
class FakeLocationGateway implements LocationGateway {
  FakeLocationGateway({this.position = const GeoPoint(33.5102, 36.2765), this.failure});

  GeoPoint position;
  AppFailure? failure;
  int reads = 0;
  int settingsOpened = 0;

  @override
  Future<GeoPoint> currentPosition() async {
    reads++;
    final AppFailure? f = failure;
    if (f != null) throw f;
    return position;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}
