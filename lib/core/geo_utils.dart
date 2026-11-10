import 'dart:math' as math;
import 'package:proj4dart/proj4dart.dart';

/// Konversi WGS84 <-> UTM untuk zona yang dipilih dari lokasi data.
class UtmConverter {
  final int zone;
  final bool south;
  late final Projection _utm;

  UtmConverter({required this.zone, required this.south}) {
    final code = (south ? 32700 : 32600) + zone;
    final def = '+proj=utm +zone=$zone ${south ? '+south ' : ''}+datum=WGS84 +units=m +no_defs';
    _utm = Projection.add('EPSG:$code', def);
  }

  factory UtmConverter.forLocation(double lat, double lon) {
    final zone = (((lon + 180) / 6).floor() % 60) + 1;
    return UtmConverter(zone: zone, south: lat < 0);
  }

  int get epsg => (south ? 32700 : 32600) + zone;

  /// Mengembalikan (easting, northing).
  (double, double) toUtm(double lat, double lon) {
    final p = Projection.WGS84.transform(_utm, Point(x: lon, y: lat));
    return (p.x, p.y);
  }

  /// Mengembalikan (lat, lon).
  (double, double) toLatLon(double e, double n) {
    final p = _utm.transform(Projection.WGS84, Point(x: e, y: n));
    return (p.y, p.x);
  }
}

double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371008.8;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
