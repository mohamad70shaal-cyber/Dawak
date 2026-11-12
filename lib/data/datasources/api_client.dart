/// A table query. Only the filters the app needs are modelled; the Supabase implementation maps them to
/// PostgREST and tests interpret them with an in-memory fake.
class Query {
  const Query(
    this.table, {
    this.columns = '*',
    this.eq = const <String, Object>{},
    this.neq = const <String, Object>{},
    this.inList = const <String, List<Object>>{},
    this.gte = const <String, Object>{},
    this.lte = const <String, Object>{},
    this.lt = const <String, Object>{},
    this.isNull = const <String>[],
    this.notNull = const <String>[],
    this.orFilter,
    this.orReferencedTable,
    this.orderBy,
    this.ascending = true,
    this.secondOrderBy,
    this.secondAscending = true,
    this.limit,
    this.offset,
  });

  final String table;

  /// PostgREST select list, e.g. `*, medicines(name_ar,name_en)`.
  final String columns;
  final Map<String, Object> eq;
  final Map<String, Object> neq;
  final Map<String, List<Object>> inList;
  final Map<String, Object> gte;
  final Map<String, Object> lte;
  final Map<String, Object> lt;
  final List<String> isNull;
  final List<String> notNull;

  /// Raw PostgREST `or=(...)` expression, e.g. `status.eq.open,status.eq.in_review`.
  final String? orFilter;

  /// When set, [orFilter] applies to this embedded table (use with an `!inner` embed to filter parent rows).
  final String? orReferencedTable;
  final String? orderBy;
  final bool ascending;
  final String? secondOrderBy;
  final bool secondAscending;
  final int? limit;
  final int? offset;

  Query copyWith({int? limit, int? offset}) => Query(
        table,
        columns: columns,
        eq: eq,
        neq: neq,
        inList: inList,
        gte: gte,
        lte: lte,
        lt: lt,
        isNull: isNull,
        notNull: notNull,
        orFilter: orFilter,
        orReferencedTable: orReferencedTable,
        orderBy: orderBy,
        ascending: ascending,
        secondOrderBy: secondOrderBy,
        secondAscending: secondAscending,
        limit: limit ?? this.limit,
        offset: offset ?? this.offset,
      );
}

/// The only seam between the app and the backend for data. Repositories depend on this interface;
/// everything that throws is converted to `AppFailure` by the implementation.
abstract class ApiClient {
  /// Calls a Postgres function (`supabase.rpc`). Returns the decoded JSON (Map, List or scalar).
  Future<dynamic> rpc(String fn, [Map<String, dynamic>? params]);

  Future<List<Map<String, dynamic>>> select(Query query);

  /// First matching row or null.
  Future<Map<String, dynamic>?> selectOne(Query query);

  /// Updates rows matching [eq]; returns the number of rows the server reports as changed (RLS may yield 0).
  Future<int> update(String table, Map<String, dynamic> values, {required Map<String, Object> eq});

  Future<Map<String, dynamic>> insert(String table, Map<String, dynamic> values);

  /// Inserts without reading the row back (for tables the inserter may not SELECT, e.g. reports by others).
  Future<void> insertOnly(String table, Map<String, dynamic> values);
}

enum AuthEventKind { signedIn, signedOut, tokenRefreshed, passwordRecovery, userUpdated, other }

abstract class AuthGateway {
  bool get hasSession;
  String? get currentUserId;
  String? get currentEmail;
  Stream<AuthEventKind> get events;

  Future<void> signIn({required String email, required String password});

  /// Returns true when a session was opened immediately (e-mail confirmation off), false when the user must
  /// confirm the address first.
  Future<bool> signUp({required String email, required String password, required String displayName});

  Future<void> signOut();
  Future<void> resetPassword(String email);
  Future<void> resendConfirmation(String email);
  Future<void> updatePassword(String newPassword);
}

abstract class FileStore {
  /// Uploads a licence document to the private bucket under `<user-id>/<fileName>`; returns the object path.
  Future<String> uploadLicense({required String userId, required String fileName, required List<int> bytes, required String contentType});

  /// Short-lived link for an admin to view a licence document.
  Future<String> signedLicenseUrl(String path, {Duration expiresIn = const Duration(minutes: 10)});
}
