import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A failure the UI can show. It never carries raw database or server text: the screen resolves
/// [messageKey] through the translation table, so users only ever see localized, human wording.
class AppFailure implements Exception {
  const AppFailure(this.code, {this.details = const <String, dynamic>{}});

  /// Machine code, e.g. `price_changed` (see `database_schema.md` §7, plus client-side codes).
  final String code;

  /// Parsed `DETAIL` of the database error (product ids, availability, ...). Used for friendly hints only.
  final Map<String, dynamic> details;

  /// Codes raised by the SQL functions (`RAISE EXCEPTION ... MESSAGE = <code>`).
  static const Set<String> serverCodes = <String>{
    'not_authenticated',
    'account_suspended',
    'forbidden',
    'pharmacy_not_active',
    'invalid_input',
    'price_changed',
    'product_unavailable',
    'invalid_transition',
    'reservation_expired',
    'reference_mismatch',
    'rate_limited',
    'too_many_pending',
    'too_many_requests',
    'request_closed',
    'duplicate_request',
    'not_found',
    'internal_error',
    'append_only',
  };

  /// Translation key for the user-facing message.
  String get messageKey => 'err_$code';

  bool get isSessionProblem => code == 'not_authenticated';

  bool get isNetwork => code == 'network';

  @override
  String toString() => 'AppFailure($code)';

  /// Converts anything thrown by a data source into an [AppFailure].
  factory AppFailure.from(Object error) {
    if (error is AppFailure) return error;
    if (kDebugMode) {
      debugPrint('AppFailure.from: ${error.runtimeType}: $error');
    }

    if (error is PostgrestException) {
      final String message = error.message.trim();
      if (serverCodes.contains(message)) {
        return AppFailure(message, details: _parseDetails(error.details));
      }
      switch (error.code) {
        case '42501':
          return const AppFailure('forbidden');
        case '22P02':
        case '22023':
        case '23514':
        case '23502':
          return const AppFailure('invalid_input');
        case '23505':
          return const AppFailure('duplicate_request');
        case 'PGRST116':
          return const AppFailure('not_found');
        case 'PGRST301':
        case 'PGRST302':
          return const AppFailure('not_authenticated');
      }
      final String lower = message.toLowerCase();
      if (lower.contains('jwt') && lower.contains('expired')) {
        return const AppFailure('not_authenticated');
      }
      return const AppFailure('unknown');
    }

    if (error is AuthException) {
      final String m = error.message.toLowerCase();
      if (m.contains('invalid login credentials') || m.contains('invalid credentials')) {
        return const AppFailure('invalid_credentials');
      }
      if (m.contains('email not confirmed')) return const AppFailure('email_not_confirmed');
      if (m.contains('already registered') || m.contains('already been registered') || m.contains('user_already_exists')) {
        return const AppFailure('email_taken');
      }
      if (m.contains('password') && (m.contains('weak') || m.contains('at least') || m.contains('short'))) {
        return const AppFailure('weak_password');
      }
      if (m.contains('rate limit') || m.contains('too many') || m.contains('seconds')) {
        return const AppFailure('rate_limited');
      }
      if (m.contains('jwt') || m.contains('refresh token') || m.contains('session')) {
        return const AppFailure('not_authenticated');
      }
      if (m.contains('socket') || m.contains('network') || m.contains('connection')) {
        return const AppFailure('network');
      }
      return const AppFailure('auth_failed');
    }

    if (error is StorageException) {
      if (error.statusCode == '413') return const AppFailure('file_too_large');
      return const AppFailure('storage_failed');
    }

    if (error is SocketException || error is TimeoutException || error is HandshakeException) {
      return const AppFailure('network');
    }
    // package:http's ClientException is not imported here on purpose (transitive dependency).
    if (error.runtimeType.toString().contains('ClientException')) {
      return const AppFailure('network');
    }
    return const AppFailure('unknown');
  }

  static Map<String, dynamic> _parseDetails(Object? raw) {
    try {
      if (raw is Map) return Map<String, dynamic>.from(raw);
      if (raw is String && raw.trim().startsWith('{')) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Details are only a hint; ignore anything unparsable.
    }
    return const <String, dynamic>{};
  }
}
