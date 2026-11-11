enum Role { standalone, base, rover }

class SurveyPoint {
  final String id;
  final String name;
  final double lat, lon, gnssAlt, accuracy, stdH, tMs;
  final double? pressure;
  final int nUsed;
  final String qa; // baik | cukup | buruk
  final String note;
  final String source; // phone | rtk
  final int rtkQuality; // 4 = RTK fixed, 5 = RTK float, 0 = bukan RTK

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
    this.source = 'phone',
    this.rtkQuality = 0,
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
        'source': source,
        'rtkQuality': rtkQuality,
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
        source: j['source'] ?? 'phone',
        rtkQuality: (j['rtkQuality'] as num?)?.toInt() ?? 0,
      );
}
