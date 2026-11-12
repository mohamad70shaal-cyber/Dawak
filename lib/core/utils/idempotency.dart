import 'dart:math';

final Random _secure = Random.secure();

/// A random key (>= 8 and <= 100 characters, as required by the database) that makes a retried
/// "create" request return the first result instead of creating a duplicate.
String newIdempotencyKey([String prefix = 'k']) {
  final StringBuffer b = StringBuffer(prefix)..write('-');
  for (int i = 0; i < 24; i++) {
    b.write(_secure.nextInt(16).toRadixString(16));
  }
  return b.toString();
}

/// Holds one idempotency key per distinct request payload.
///
/// The same key is reused while the user retries the *same* request (network error, double tap) and is
/// replaced as soon as the payload changes, because the server rejects a key reused with different content.
/// Call [clear] after the server confirmed success.
class IdempotencyKeeper {
  String? _key;
  String? _signature;

  String keyFor(String signature, [String prefix = 'k']) {
    if (_key == null || _signature != signature) {
      _key = newIdempotencyKey(prefix);
      _signature = signature;
    }
    return _key!;
  }

  void clear() {
    _key = null;
    _signature = null;
  }
}
