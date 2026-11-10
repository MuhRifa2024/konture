import '../contour/contour.dart';
import '../core/geo_utils.dart';

Map<String, dynamic> pointFeature({
  required String id,
  required double lat,
  required double lon,
  required double z,
  required Map<String, dynamic> props,
}) =>
    {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [lon, lat, double.parse(z.toStringAsFixed(3))]
      },
      'properties': {'id': id, 'elevation': double.parse(z.toStringAsFixed(3)), ...props},
    };

/// Kontur (koordinat UTM) -> Feature LineString WGS84 (RFC 7946).
List<Map<String, dynamic>> contourFeatures(
  List<ContourLine> lines,
  UtmConverter utm, {
  required double interval,
  String source = 'survey',
  String accuracyClass = 'standar',
}) {
  return [
    for (final l in lines)
      {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in l.points)
              () {
                final (lat, lon) = utm.toLatLon(p.$1, p.$2);
                return [lon, lat];
              }()
          ]
        },
        'properties': {
          'elevation': l.elevation,
          'interval': interval,
          'source': source,
          'accuracy_class': accuracyClass,
        },
      }
  ];
}

Map<String, dynamic> featureCollection(List<Map<String, dynamic>> features) =>
    {'type': 'FeatureCollection', 'features': features};

/// Menggabungkan fitur baru ke GeoJSON lama. TIDAK mengubah [old].
/// Titik baru yang berjarak < [conflictMeters] dari titik lama diberi
/// properti `conflict_with` agar bisa ditinjau manual.
Map<String, dynamic> mergeGeoJson(
  Map<String, dynamic> old,
  List<Map<String, dynamic>> newFeatures, {
  double conflictMeters = 2,
  String source = 'survey',
}) {
  final oldFeatures = [
    for (final f in (old['features'] as List? ?? const [])) Map<String, dynamic>.from(f as Map)
  ];

  final oldPoints = <(String, double, double)>[];
  for (var i = 0; i < oldFeatures.length; i++) {
    final g = oldFeatures[i]['geometry'];
    if (g is Map && g['type'] == 'Point') {
      final c = g['coordinates'] as List;
      final props = oldFeatures[i]['properties'] as Map?;
      oldPoints.add(('${props?['id'] ?? props?['name'] ?? i}', (c[1] as num).toDouble(), (c[0] as num).toDouble()));
    }
  }

  final merged = <Map<String, dynamic>>[...oldFeatures];
  for (final nf in newFeatures) {
    final f = Map<String, dynamic>.from(nf);
    final props = Map<String, dynamic>.from(f['properties'] as Map);
    props['source'] ??= source;
    final g = f['geometry'] as Map;
    if (g['type'] == 'Point') {
      final c = g['coordinates'] as List;
      for (final op in oldPoints) {
        if (haversineMeters((c[1] as num).toDouble(), (c[0] as num).toDouble(), op.$2, op.$3) < conflictMeters) {
          props['conflict_with'] = op.$1;
          break;
        }
      }
    }
    f['properties'] = props;
    merged.add(f);
  }
  return {...old, 'type': 'FeatureCollection', 'features': merged};
}
