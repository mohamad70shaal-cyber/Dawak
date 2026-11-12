import 'dart:async';

import 'package:dawak/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('server machine codes pass through with parsed details', () {
    final AppFailure f = AppFailure.from(PostgrestException(
      message: 'product_unavailable',
      code: 'P0001',
      details: '{"product_id":"abc","name":"Panadol"}',
    ));
    expect(f.code, 'product_unavailable');
    expect(f.details['product_id'], 'abc');
    expect(f.messageKey, 'err_product_unavailable');
  });

  test('availability-request codes are server codes; removed stock codes are not', () {
    expect(AppFailure.from(PostgrestException(message: 'request_closed', code: 'P0001')).code, 'request_closed');
    expect(AppFailure.from(PostgrestException(message: 'too_many_requests', code: 'P0001')).code, 'too_many_requests');
    // The stock model is gone: an old message must not be trusted as a code.
    expect(AppFailure.from(PostgrestException(message: 'insufficient_stock', code: 'P0001')).code, 'unknown');
    expect(AppFailure.from(PostgrestException(message: 'stock_below_reserved', code: 'P0001')).code, 'unknown');
  });

  test('raw database text never becomes a code', () {
    final AppFailure f = AppFailure.from(PostgrestException(message: 'relation "x" does not exist', code: '42P01'));
    expect(f.code, 'unknown');
    expect(f.toString().contains('relation'), isFalse);
  });

  test('SQLSTATE fallbacks', () {
    expect(AppFailure.from(PostgrestException(message: 'x', code: '42501')).code, 'forbidden');
    expect(AppFailure.from(PostgrestException(message: 'x', code: '23505')).code, 'duplicate_request');
    expect(AppFailure.from(PostgrestException(message: 'x', code: '22P02')).code, 'invalid_input');
    expect(AppFailure.from(PostgrestException(message: 'x', code: 'PGRST301')).code, 'not_authenticated');
  });

  test('expired JWT means not authenticated', () {
    expect(AppFailure.from(PostgrestException(message: 'JWT expired', code: 'PGRST303')).code, 'not_authenticated');
  });

  test('auth errors', () {
    expect(AppFailure.from(AuthException('Invalid login credentials')).code, 'invalid_credentials');
    expect(AppFailure.from(AuthException('Email not confirmed')).code, 'email_not_confirmed');
    expect(AppFailure.from(AuthException('User already registered')).code, 'email_taken');
  });

  test('timeouts are network failures', () {
    expect(AppFailure.from(TimeoutException('slow')).code, 'network');
  });

  test('AppFailure passes through unchanged', () {
    const AppFailure f = AppFailure('forbidden');
    expect(identical(AppFailure.from(f), f), isTrue);
  });
}
