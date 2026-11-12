import '../../data/models/geo.dart';

/// Reads a position from what a person pastes: plain coordinates (`33.5102, 36.2765`, Arabic digits and commas
/// accepted, optional `N`/`E` letters) or a map link that contains them (`@lat,lng`, `?q=lat,lng`, `!3d…!4d…`,
/// `geo:lat,lng`, …). Short share links (`maps.app.goo.gl/...`) hide the coordinates behind a redirect, which
/// the app cannot follow offline: [isShortLink] lets the screen explain that.
class GeoParse {
  const GeoParse._();

  static const String _num = r'(-?\d{1,3}(?:\.\d+)?)';

  static final List<RegExp> _linkPatterns = <RegExp>[
    RegExp('@$_num,\\s*$_num'),
    RegExp('!3d$_num!4d$_num'),
    RegExp('[?&](?:q|ll|query|destination|center|daddr|saddr)=\\s*$_num\\s*,\\s*$_num', caseSensitive: false),
    RegExp('^geo:$_num,\\s*$_num', caseSensitive: false),
  ];

  static final RegExp _plain = RegExp('^\\(?\\s*$_num\\s*[,;\\s]\\s*$_num\\s*\\)?\$');

  static final RegExp _hemisphere = RegExp(
    r'^(\d{1,3}(?:\.\d+)?)\s*°?\s*([NSns])\s*[,;\s]?\s*(\d{1,3}(?:\.\d+)?)\s*°?\s*([EWew])$',
  );

  /// Null when nothing usable was found (or the numbers are out of range / (0, 0)).
  static GeoPoint? parse(String? input) {
    if (input == null) return null;
    String s = _asciiDigitsAndSeparators(input.trim());
    if (s.isEmpty) return null;
    try {
      s = Uri.decodeFull(s);
    } catch (_) {
      // Keep the raw text: a stray '%' is not worth failing for.
    }
    s = s.replaceAll('+', ' ').trim();

    for (final RegExp p in _linkPatterns) {
      final RegExpMatch? m = p.firstMatch(s);
      if (m != null) {
        final GeoPoint? g = GeoPoint.tryCreate(double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
        if (g != null) return g;
      }
    }

    final RegExpMatch? h = _hemisphere.firstMatch(s);
    if (h != null) {
      double? lat = double.tryParse(h.group(1)!);
      double? lng = double.tryParse(h.group(3)!);
      if (lat != null && lng != null) {
        if (h.group(2)!.toUpperCase() == 'S') lat = -lat;
        if (h.group(4)!.toUpperCase() == 'W') lng = -lng;
        return GeoPoint.tryCreate(lat, lng);
      }
    }

    final RegExpMatch? m = _plain.firstMatch(s);
    if (m != null) return GeoPoint.tryCreate(double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    return null;
  }

  /// A share link whose coordinates are only available after a redirect.
  static bool isShortLink(String? input) {
    final String s = (input ?? '').toLowerCase();
    return s.contains('maps.app.goo.gl') || s.contains('goo.gl/maps') || s.contains('g.co/kgs');
  }

  /// Arabic-Indic / Persian digits → ASCII, Arabic comma and semicolon → ASCII, Arabic decimal separator → '.'.
  static String _asciiDigitsAndSeparators(String input) {
    final StringBuffer b = StringBuffer();
    for (final int r in input.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(0x30 + (r - 0x0660));
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(0x30 + (r - 0x06F0));
      } else if (r == 0x060C || r == 0x061B) {
        b.write(',');
      } else if (r == 0x066B) {
        b.write('.');
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }
}
