import '../../data/models/geo.dart';

/// Links that open a place in whatever map app the phone has (they are plain https links, so they also work in a browser).
class MapLinks {
  const MapLinks._();

  /// Turn-by-turn directions to [to] from the user's current position (the map app asks for it).
  static Uri directions(GeoPoint to) => Uri.https('www.google.com', '/maps/dir/', <String, String>{
        'api': '1',
        'destination': '${to.latitude},${to.longitude}',
      });

  /// A pin on [at] (no route).
  static Uri place(GeoPoint at) => Uri.https('www.google.com', '/maps/search/', <String, String>{
        'api': '1',
        'query': '${at.latitude},${at.longitude}',
      });
}
