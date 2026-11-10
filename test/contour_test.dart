import 'package:flutter_test/flutter_test.dart';
import 'package:kontur_survey/contour/contour.dart';

void main() {
  test('bidang z = x menghasilkan kontur lurus di x = level', () {
    final nx = 11, ny = 11;
    final v = List.generate(ny, (j) => List.generate(nx, (i) => i.toDouble()));
    final g = Grid(0, 0, 1, nx, ny, v);
    final lines = marchingSquares(g, [5.5]);
    expect(lines.length, 1);
    for (final p in lines.first.points) {
      expect(p.$1, closeTo(5.5, 1e-9));
    }
  });

  test('pipeline membuat kontur dari titik miring', () {
    final pts = <XYZ>[
      for (var x = 0; x <= 100; x += 20)
        for (var y = 0; y <= 100; y += 20) XYZ(x.toDouble(), y.toDouble(), x * 0.1)
    ];
    final lines = buildContours(pts, 2);
    expect(lines, isNotEmpty);
  });
}
