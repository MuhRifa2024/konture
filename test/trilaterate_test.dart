import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:kontur_survey/core/trilaterate.dart';

double _d(Anchor a, double x, double y, double z) =>
    math.sqrt(math.pow(a.x - x, 2) + math.pow(a.y - y, 2) + math.pow(a.z - z, 2)).toDouble();

void main() {
  const anchors = [
    Anchor(0, 0, 0),
    Anchor(100, 0, 5),
    Anchor(0, 100, 10),
    Anchor(100, 100, 30),
    Anchor(50, 50, 60),
  ];

  test('3D tanpa noise menemukan posisi benar', () {
    const tx = 37.0, ty = 62.0, tz = 12.5;
    final d = [for (final a in anchors) _d(a, tx, ty, tz)];
    final r = trilaterate(anchors, d);
    expect(r.x, closeTo(tx, 1e-4));
    expect(r.y, closeTo(ty, 1e-4));
    expect(r.z, closeTo(tz, 1e-4));
    expect(r.rms, lessThan(1e-4));
  });

  test('3D dengan noise 1 cm: galat < 5 cm', () {
    const tx = 20.0, ty = 80.0, tz = 8.0;
    final rnd = math.Random(1);
    final d = [for (final a in anchors) _d(a, tx, ty, tz) + (rnd.nextDouble() - 0.5) * 0.02];
    final r = trilaterate(anchors, d);
    final err = math.sqrt(math.pow(r.x - tx, 2) + math.pow(r.y - ty, 2) + math.pow(r.z - tz, 2));
    expect(err, lessThan(0.05));
  });

  test('2D dengan z dikunci', () {
    const tx = 40.0, ty = 30.0, tz = 3.0;
    final a3 = anchors.take(3).toList();
    final d = [for (final a in a3) _d(a, tx, ty, tz)];
    final r = trilaterate(a3, d, is2D: true, fixedZ: tz);
    expect(r.x, closeTo(tx, 1e-3));
    expect(r.y, closeTo(ty, 1e-3));
  });

  test('acuan kurang dari minimum melempar galat', () {
    expect(() => trilaterate(anchors.take(3).toList(), [1, 2, 3]), throwsArgumentError);
  });
}
