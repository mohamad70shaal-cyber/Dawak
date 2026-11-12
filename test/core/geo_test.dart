// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/utils/geo_parse.dart';
import 'package:dawak/core/utils/map_links.dart';
import 'package:dawak/data/models/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoPoint', () {
    test('isValid mirrors the database check: finite, in range, not (0, 0)', () {
      expect(GeoPoint.isValid(33.5, 36.3), isTrue);
      expect(GeoPoint.isValid(-90, 180), isTrue);
      expect(GeoPoint.isValid(0, 0), isFalse, reason: 'the "no fix" value');
      expect(GeoPoint.isValid(0, 36.3), isTrue);
      expect(GeoPoint.isValid(90.01, 0), isFalse);
      expect(GeoPoint.isValid(0, 180.5), isFalse);
      expect(GeoPoint.isValid(double.nan, 1), isFalse);
      expect(GeoPoint.isValid(1, double.infinity), isFalse);
      expect(GeoPoint.isValid(null, 1), isFalse);
      expect(GeoPoint.isValid(1, null), isFalse);
    });

    test('tryCreate reads numbers, numeric strings and nulls', () {
      expect(GeoPoint.tryCreate(33.5, 36.3), const GeoPoint(33.5, 36.3));
      expect(GeoPoint.tryCreate('33.5', '36.3'), const GeoPoint(33.5, 36.3));
      expect(GeoPoint.tryCreate(33, 36), const GeoPoint(33, 36));
      expect(GeoPoint.tryCreate(null, 36.3), isNull);
      expect(GeoPoint.tryCreate('abc', 36.3), isNull);
      expect(GeoPoint.tryCreate(0, 0), isNull);
    });

    test('distance: one degree of latitude is about 111 km, symmetric, zero for the same point', () {
      const GeoPoint a = GeoPoint(0.5, 10);
      const GeoPoint b = GeoPoint(1.5, 10);
      expect(a.distanceKmTo(b), closeTo(111.19, 0.1));
      expect(b.distanceKmTo(a), closeTo(a.distanceKmTo(b), 1e-9));
      expect(a.distanceKmTo(a), 0);
    });

    test('distance between Damascus and Homs is roughly 140 km', () {
      const GeoPoint damascus = GeoPoint(33.5102, 36.2765);
      const GeoPoint homs = GeoPoint(34.7324, 36.7137);
      expect(damascus.distanceKmTo(homs), closeTo(141.7, 2));
    });

    test('nearly opposite points give a finite distance (no NaN from rounding)', () {
      const GeoPoint a = GeoPoint(10, 10);
      const GeoPoint b = GeoPoint(-10, -170);
      expect(a.distanceKmTo(b).isFinite, isTrue);
      expect(a.distanceKmTo(b), greaterThan(19000));
    });

    test('label always uses a dot and five decimals; equality is by value', () {
      expect(const GeoPoint(33.5102, 36.2765).label, '33.51020, 36.27650');
      expect(const GeoPoint(1, 2) == const GeoPoint(1, 2), isTrue);
      expect(const GeoPoint(1, 2) == const GeoPoint(1, 3), isFalse);
      expect(const GeoPoint(1, 2).hashCode, const GeoPoint(1, 2).hashCode);
    });
  });

  group('GeoParse', () {
    void expectPoint(String input, double lat, double lng) {
      final GeoPoint? p = GeoParse.parse(input);
      expect(p, isNotNull, reason: input);
      expect(p!.latitude, closeTo(lat, 1e-9), reason: input);
      expect(p.longitude, closeTo(lng, 1e-9), reason: input);
    }

    test('plain coordinates with a comma, a semicolon, a space or brackets', () {
      expectPoint('33.5102, 36.2765', 33.5102, 36.2765);
      expectPoint('33.5102,36.2765', 33.5102, 36.2765);
      expectPoint('33.5102; 36.2765', 33.5102, 36.2765);
      expectPoint('33.5102 36.2765', 33.5102, 36.2765);
      expectPoint('(33.5102, 36.2765)', 33.5102, 36.2765);
      expectPoint('  33.5102,36.2765  ', 33.5102, 36.2765);
      expectPoint('-33.5, -70.6', -33.5, -70.6);
    });

    test('Arabic digits, the Arabic comma and the Arabic decimal separator', () {
      expectPoint('٣٣٫٥١٠٢، ٣٦٫٢٧٦٥', 33.5102, 36.2765);
      expectPoint('۳۳٫۵, ۳۶٫۲', 33.5, 36.2);
    });

    test('letters for the hemisphere', () {
      expectPoint('33.5102 N, 36.2765 E', 33.5102, 36.2765);
      expectPoint('33.5 S, 70.6 W', -33.5, -70.6);
      expectPoint('33.5°N 36.2°E', 33.5, 36.2);
    });

    test('Google Maps links in their common shapes', () {
      expectPoint('https://www.google.com/maps/place/Shop/@33.4,36.2,17z/data=!3m1', 33.4, 36.2);
      expectPoint('https://www.google.com/maps/place/x/data=!4m5!3m4!1s0x0:0x0!8m2!3d33.5102!4d36.2765', 33.5102, 36.2765);
      expectPoint('https://maps.google.com/?q=33.5,36.3', 33.5, 36.3);
      expectPoint('https://www.google.com/maps/dir/?api=1&destination=33.5102%2C36.2765', 33.5102, 36.2765);
      expectPoint('geo:33.5,36.3', 33.5, 36.3);
    });

    test('nothing usable gives null, never a guess', () {
      expect(GeoParse.parse(null), isNull);
      expect(GeoParse.parse(''), isNull);
      expect(GeoParse.parse('   '), isNull);
      expect(GeoParse.parse('قرب جامع المزة'), isNull);
      expect(GeoParse.parse('33.5'), isNull);
      expect(GeoParse.parse('33.5, abc'), isNull);
    });

    test('out of range numbers and the null island are refused', () {
      expect(GeoParse.parse('0, 0'), isNull);
      expect(GeoParse.parse('95.2, 36.2'), isNull);
      expect(GeoParse.parse('33.5, 190'), isNull);
      expect(GeoParse.parse('https://maps.google.com/?q=0,0'), isNull);
    });

    test('short share links are recognised, and they hold no coordinates to read', () {
      expect(GeoParse.isShortLink('https://maps.app.goo.gl/AbCdEf123'), isTrue);
      expect(GeoParse.isShortLink('https://goo.gl/maps/xyz'), isTrue);
      expect(GeoParse.isShortLink('https://g.co/kgs/abc'), isTrue);
      expect(GeoParse.isShortLink('https://www.google.com/maps/@33.4,36.2,17z'), isFalse);
      expect(GeoParse.isShortLink(null), isFalse);
      expect(GeoParse.parse('https://maps.app.goo.gl/AbCdEf123'), isNull);
    });
  });

  group('MapLinks', () {
    test('directions go to the pharmacy and let the map app use the customer\'s own position', () {
      final Uri u = MapLinks.directions(const GeoPoint(33.5102, 36.2765));
      expect(u.scheme, 'https');
      expect(u.host, 'www.google.com');
      expect(u.path, '/maps/dir/');
      expect(u.queryParameters['api'], '1');
      expect(u.queryParameters['destination'], '33.5102,36.2765');
      expect(u.queryParameters.containsKey('origin'), isFalse, reason: 'the customer\'s position is never put in a link');
    });

    test('a place link is a pin without a route', () {
      final Uri u = MapLinks.place(const GeoPoint(33.5102, 36.2765));
      expect(u.path, '/maps/search/');
      expect(u.queryParameters['query'], '33.5102,36.2765');
    });

    test('what the app builds can be read back by GeoParse', () {
      const GeoPoint p = GeoPoint(33.5102, 36.2765);
      expect(GeoParse.parse(MapLinks.directions(p).toString()), p);
      expect(GeoParse.parse(MapLinks.place(p).toString()), p);
    });
  });
}
