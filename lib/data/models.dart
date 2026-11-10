enum Role { standalone, base, rover }

class SurveyPoint {
  final String id;
  final String name;
  final double lat, lon, gnssAlt, accuracy, stdH, tMs;
  final double? pressure;
  final int nUsed;
  final String qa; // baik | cukup | buruk
  final String note;

  const SurveyPoint({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.gnssAlt,
    required this.accuracy,
    required this.stdH,
    required this.tMs,
    required this.pressure,
    required this.nUsed,
    required this.qa,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lon': lon,
        'gnssAlt': gnssAlt,
        'accuracy': accuracy,
        'stdH': stdH,
        'tMs': tMs,
        'pressure': pressure,
        'nUsed': nUsed,
        'qa': qa,
        'note': note,
      };

  factory SurveyPoint.fromJson(Map<String, dynamic> j) => SurveyPoint(
        id: j['id'],
        name: j['name'],
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        gnssAlt: (j['gnssAlt'] as num).toDouble(),
        accuracy: (j['accuracy'] as num).toDouble(),
        stdH: (j['stdH'] as num).toDouble(),
        tMs: (j['tMs'] as num).toDouble(),
        pressure: (j['pressure'] as num?)?.toDouble(),
        nUsed: j['nUsed'],
        qa: j['qa'],
        note: j['note'] ?? '',
      );
}
