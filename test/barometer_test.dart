import 'package:flutter_test/flutter_test.dart';
import 'package:kontur_survey/core/barometer.dart';

void main() {
  test('1 hPa pada permukaan laut ~ 8 m', () {
    final h = heightDifference(pBase: 1013.25, pRover: 1012.25);
    expect(h, closeTo(8.4, 0.3));
  });
  test('rover lebih tinggi -> tekanan lebih rendah -> beda tinggi positif', () {
    expect(heightDifference(pBase: 1000, pRover: 990), greaterThan(0));
  });
  test('interpolasi log tekanan', () {
    final log = PressureLog([[0, 1000], [10000, 990]]);
    expect(log.at(5000), closeTo(995, 1e-9));
    expect(log.at(1e9), isNull);
  });
}
