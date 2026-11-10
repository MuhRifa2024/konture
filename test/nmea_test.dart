import 'package:flutter_test/flutter_test.dart';
import 'package:kontur_survey/sensors/nmea_parser.dart';

void main() {
  const gga = r'$GPGGA,092750.000,5321.6802,N,00630.3372,W,1,8,1.03,61.7,M,55.2,M,,*76';

  test('checksum valid', () => expect(nmeaChecksumValid(gga), isTrue));
  test('checksum salah ditolak', () => expect(nmeaChecksumValid(gga.replaceFirst('*76', '*00')), isFalse));

  test('parse GGA', () {
    final f = parseGga(gga)!;
    expect(f.lat, closeTo(53.361337, 1e-5));
    expect(f.lon, closeTo(-6.505620, 1e-5));
    expect(f.satellites, 8);
    expect(f.altitude, closeTo(61.7, 1e-9));
  });

  test('buffer menyusun kalimat dari potongan', () {
    final b = NmeaLineBuffer();
    expect(b.add(gga.substring(0, 20)), isEmpty);
    expect(b.add('${gga.substring(20)}\r\n'), [gga]);
  });
}
