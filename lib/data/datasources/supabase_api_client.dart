import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import 'api_client.dart';

const Duration _timeout = Duration(seconds: 25);

/// Runs [job], converting any thrown error into an [AppFailure] (never leaking raw messages).
Future<T> _guard<T>(Future<T> Function() job) async {
  try {
    return await job().timeout(_timeout);
  } catch (e) {
    throw AppFailure.from(e);
  }
}

class SupabaseApiClient implements ApiClient {
  SupabaseApiClient(this._db);

  final SupabaseClient _db;

  @override
  Future<dynamic> rpc(String fn, [Map<String, dynamic>? params]) {
    return _guard<dynamic>(() async {
      final dynamic result = await _db.rpc(fn, params: params);
      return result;
    });
  }

  @override
  Future<List<Map<String, dynamic>>> select(Query q) {
    return _guard<List<Map<String, dynamic>>>(() async {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> f = _db.from(q.table).select(q.columns);
      q.eq.forEach((String k, Object v) => f = f.eq(k, v));
      q.neq.forEach((String k, Object v) => f = f.neq(k, v));
      q.inList.forEach((String k, List<Object> v) => f = f.inFilter(k, v));
      q.gte.forEach((String k, Object v) => f = f.gte(k, v));
      q.lte.forEach((String k, Object v) => f = f.lte(k, v));
      q.lt.forEach((String k, Object v) => f = f.lt(k, v));
      for (final String c in q.isNull) {
        f = f.isFilter(c, null);
      }
      for (final String c in q.notNull) {
        f = f.not(c, 'is', null);
      }
      final String? orExpr = q.orFilter;
      if (orExpr != null) f = f.or(orExpr, referencedTable: q.orReferencedTable);

      PostgrestTransformBuilder<List<Map<String, dynamic>>> t = f;
      if (q.orderBy != null) t = t.order(q.orderBy!, ascending: q.ascending);
      if (q.secondOrderBy != null) t = t.order(q.secondOrderBy!, ascending: q.secondAscending);
      final int? limit = q.limit;
      if (limit != null) {
        final int offset = q.offset ?? 0;
        t = t.range(offset, offset + limit - 1);
      }
      final List<Map<String, dynamic>> rows = await t;
      return rows;
    });
  }

  @override
  Future<Map<String, dynamic>?> selectOne(Query q) async {
    final List<Map<String, dynamic>> rows = await select(q.copyWith(limit: 1));
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<int> update(String table, Map<String, dynamic> values, {required Map<String, Object> eq}) {
    return _guard<int>(() async {
      // `update()` is typed PostgrestFilterBuilder<dynamic>; keep the inferred type (no explicit annotation).
      var f = _db.from(table).update(values);
      eq.forEach((String k, Object v) => f = f.eq(k, v));
      final List<Map<String, dynamic>> rows = await f.select();
      return rows.length;
    });
  }

  @override
  Future<Map<String, dynamic>> insert(String table, Map<String, dynamic> values) {
    return _guard<Map<String, dynamic>>(() async {
      final Map<String, dynamic> row = await _db.from(table).insert(values).select().single();
      return row;
    });
  }

  @override
  Future<void> insertOnly(String table, Map<String, dynamic> values) {
    return _guard<void>(() async {
      await _db.from(table).insert(values);
    });
  }
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  String? get currentEmail => _auth.currentUser?.email;

  @override
  Stream<AuthEventKind> get events => _auth.onAuthStateChange.map((AuthState s) {
        switch (s.event) {
          case AuthChangeEvent.signedIn:
            return AuthEventKind.signedIn;
          case AuthChangeEvent.signedOut:
            return AuthEventKind.signedOut;
          case AuthChangeEvent.tokenRefreshed:
            return AuthEventKind.tokenRefreshed;
          case AuthChangeEvent.passwordRecovery:
            return AuthEventKind.passwordRecovery;
          case AuthChangeEvent.userUpdated:
            return AuthEventKind.userUpdated;
          default:
            return AuthEventKind.other;
        }
      });

  @override
  Future<void> signIn({required String email, required String password}) {
    return _guard<void>(() async {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    });
  }

  @override
  Future<bool> signUp({required String email, required String password, required String displayName}) {
    return _guard<bool>(() async {
      final AuthResponse res = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: <String, dynamic>{'display_name': displayName.trim()},
      );
      // With confirmation enabled Supabase returns a user but no session. An already-registered address
      // returns a user with an empty identities list (to avoid account enumeration): treat it as "email_taken".
      final List<UserIdentity>? identities = res.user?.identities;
      if (res.session == null && identities != null && identities.isEmpty) {
        throw const AppFailure('email_taken');
      }
      return res.session != null;
    });
  }

  @override
  Future<void> signOut() => _guard<void>(() async {
        await _auth.signOut();
      });

  @override
  Future<void> resetPassword(String email) => _guard<void>(() async {
        await _auth.resetPasswordForEmail(email.trim());
      });

  @override
  Future<void> resendConfirmation(String email) => _guard<void>(() async {
        await _auth.resend(type: OtpType.signup, email: email.trim());
      });

  @override
  Future<void> updatePassword(String newPassword) => _guard<void>(() async {
        await _auth.updateUser(UserAttributes(password: newPassword));
      });
}

class SupabaseFileStore implements FileStore {
  SupabaseFileStore(this._client);

  final SupabaseClient _client;

  static const String bucket = 'pharmacy-documents';

  @override
  Future<String> uploadLicense({
    required String userId,
    required String fileName,
    required List<int> bytes,
    required String contentType,
  }) {
    return _guard<String>(() async {
      final String safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final String path = '$userId/${DateTime.now().millisecondsSinceEpoch}_$safe';
      await _client.storage.from(bucket).uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
      return path;
    });
  }

  @override
  Future<String> signedLicenseUrl(String path, {Duration expiresIn = const Duration(minutes: 10)}) {
    return _guard<String>(() async {
      return _client.storage.from(bucket).createSignedUrl(path, expiresIn.inSeconds);
    });
  }
}
