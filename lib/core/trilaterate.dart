import 'dart:math' as math;
import 'linalg.dart';

class Anchor {
  final double x, y, z;
  const Anchor(this.x, this.y, this.z);
}

class TrilaterationResult {
  final double x, y, z;
  final double rms; // RMS residual (m)
  final double gdop;
  final int iterations;
  final bool converged;
  final List<double> residuals;
  const TrilaterationResult({
    required this.x,
    required this.y,
    required this.z,
    required this.rms,
    required this.gdop,
    required this.iterations,
    required this.converged,
    required this.residuals,
  });
}

/// Trilaterasi least squares (Levenberg-Marquardt).
/// 3D: minimal 4 acuan tidak sebidang. 2D: minimal 3 acuan, z dikunci ([fixedZ]).
TrilaterationResult trilaterate(
  List<Anchor> anchors,
  List<double> distances, {
  bool is2D = false,
  double? fixedZ,
  int maxIter = 100,
  double tol = 1e-7,
}) {
  final n = anchors.length;
  final dim = is2D ? 2 : 3;
  if (distances.length != n) {
    throw ArgumentError('Jumlah jarak harus sama dengan jumlah acuan');
  }
  if (n < dim + 1) {
    throw ArgumentError('Butuh minimal ${dim + 1} titik acuan untuk ${dim}D');
  }

  var cx = 0.0, cy = 0.0, cz = 0.0;
  for (final a in anchors) {
    cx += a.x;
    cy += a.y;
    cz += a.z;
  }
  cx /= n;
  cy /= n;
  cz /= n;

  var px = cx, py = cy;
  var pz = is2D ? (fixedZ ?? cz) : cz + 1.0; // offset kecil agar tidak singular

  List<double> residuals(double x, double y, double z) => [
        for (var i = 0; i < n; i++)
          math.sqrt(math.pow(x - anchors[i].x, 2) +
                  math.pow(y - anchors[i].y, 2) +
                  math.pow(z - anchors[i].z, 2)) -
              distances[i]
      ];

  double cost(List<double> r) => r.fold(0.0, (s, e) => s + e * e);

  List<List<double>> jacobian(double x, double y, double z) {
    return [
      for (var i = 0; i < n; i++)
        () {
          final dx = x - anchors[i].x, dy = y - anchors[i].y, dz = z - anchors[i].z;
          final d = math.max(math.sqrt(dx * dx + dy * dy + dz * dz), 1e-9);
          return is2D ? [dx / d, dy / d] : [dx / d, dy / d, dz / d];
        }()
    ];
  }

  List<List<double>> jtj(List<List<double>> j) => [
        for (var a = 0; a < dim; a++)
          [
            for (var b = 0; b < dim; b++)
              j.fold(0.0, (s, row) => s + row[a] * row[b])
          ]
      ];

  var lambda = 1e-3;
  var r = residuals(px, py, pz);
  var c = cost(r);
  var iter = 0;
  var converged = false;

  for (; iter < maxIter; iter++) {
    final j = jacobian(px, py, pz);
    final a = jtj(j);
    final g = [
      for (var k = 0; k < dim; k++)
        [for (var i = 0; i < n; i++) j[i][k] * r[i]].reduce((p, q) => p + q)
    ];
    // (JtJ + lambda*diag(JtJ)) dp = -Jt r
    final aa = [
      for (var i = 0; i < dim; i++)
        [for (var k = 0; k < dim; k++) a[i][k] + (i == k ? lambda * (a[i][i] + 1e-12) : 0)]
    ];
    final dp = solveLinear(aa, [for (final v in g) -v]);
    if (dp == null) break;

    final nx = px + dp[0], ny = py + dp[1], nz = is2D ? pz : pz + dp[2];
    final nr = residuals(nx, ny, nz);
    final nc = cost(nr);
    if (nc < c) {
      px = nx;
      py = ny;
      pz = nz;
      r = nr;
      c = nc;
      lambda = math.max(lambda / 10, 1e-12);
      final step = math.sqrt(dp.fold(0.0, (s, e) => s + e * e));
      if (step < tol) {
        converged = true;
        iter++;
        break;
      }
    } else {
      lambda *= 10;
      if (lambda > 1e12) break;
    }
  }

  // GDOP = sqrt(trace((JtJ)^-1))
  final jf = jacobian(px, py, pz);
  final af = jtj(jf);
  var trace = 0.0;
  var singular = false;
  for (var k = 0; k < dim; k++) {
    final e = List<double>.filled(dim, 0)..[k] = 1;
    final col = solveLinear(af, e);
    if (col == null) {
      singular = true;
      break;
    }
    trace += col[k];
  }

  return TrilaterationResult(
    x: px,
    y: py,
    z: pz,
    rms: math.sqrt(c / n),
    gdop: singular ? double.infinity : math.sqrt(trace),
    iterations: iter,
    converged: converged,
    residuals: r,
  );
}
