/// Parser NMEA untuk receiver RTK (GGA & GST).
class GgaFix {
  final double lat, lon, altitude, hdop;
  final int quality, satellites;
  final double? geoidSeparation;
  const GgaFix({
    required this.lat,
    required this.lon,
    required this.altitude,
    required this.hdop,
    required this.quality,
    required this.satellites,
    this.geoidSeparation,
  });

  String get qualityLabel => switch (quality) {
        0 => 'Tidak ada fix',
        1 => 'GNSS',
        2 => 'DGPS',
        4 => 'RTK Fixed',
        5 => 'RTK Float',
        _ => 'Lainnya ($quality)',
      };
  bool get isRtkFixed => quality == 4;
}

class GstError {
  final double stdLat, stdLon, stdAlt;
  const GstError(this.stdLat, this.stdLon, this.stdAlt);
}

bool nmeaChecksumValid(String sentence) {
  final s = sentence.trim();
  final star = s.lastIndexOf('*');
  if (!s.startsWith(r'$') || star < 0 || star + 3 > s.length) return false;
  var x = 0;
  for (final c in s.substring(1, star).codeUnits) {
    x ^= c;
  }
  final given = int.tryParse(s.substring(star + 1, star + 3), radix: 16);
  return given == x;
}

double? _coord(String v, String hemi) {
  if (v.isEmpty) return null;
  final dot = v.indexOf('.');
  if (dot < 3) return null;
  final deg = double.tryParse(v.substring(0, dot - 2));
  final min = double.tryParse(v.substring(dot - 2));
  if (deg == null || min == null) return null;
  final d = deg + min / 60;
  return (hemi == 'S' || hemi == 'W') ? -d : d;
}

GgaFix? parseGga(String sentence) {
  if (!nmeaChecksumValid(sentence)) return null;
  final body = sentence.trim().substring(1, sentence.trim().lastIndexOf('*'));
  final f = body.split(',');
  if (f.isEmpty || !f[0].endsWith('GGA') || f.length < 12) return null;
  final lat = _coord(f[2], f[3]);
  final lon = _coord(f[4], f[5]);
  final q = int.tryParse(f[6]) ?? 0;
  if (lat == null || lon == null) return null;
  return GgaFix(
    lat: lat,
    lon: lon,
    quality: q,
    satellites: int.tryParse(f[7]) ?? 0,
    hdop: double.tryParse(f[8]) ?? 99.9,
    altitude: double.tryParse(f[9]) ?? 0,
    geoidSeparation: double.tryParse(f[11]),
  );
}

GstError? parseGst(String sentence) {
  if (!nmeaChecksumValid(sentence)) return null;
  final body = sentence.trim().substring(1, sentence.trim().lastIndexOf('*'));
  final f = body.split(',');
  if (f.isEmpty || !f[0].endsWith('GST') || f.length < 9) return null;
  final a = double.tryParse(f[6]), b = double.tryParse(f[7]), c = double.tryParse(f[8]);
  if (a == null || b == null || c == null) return null;
  return GstError(a, b, c);
}

/// Menyusun potongan data BLE/serial menjadi kalimat NMEA utuh.
class NmeaLineBuffer {
  final StringBuffer _buf = StringBuffer();
  List<String> add(String chunk) {
    _buf.write(chunk);
    final text = _buf.toString();
    final lines = text.split(RegExp(r'\r?\n'));
    _buf
      ..clear()
      ..write(lines.removeLast());
    return lines.where((l) => l.startsWith(r'$')).toList();
  }
}
