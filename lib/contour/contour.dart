import 'dart:math' as math;

typedef Pt = (double, double);

class XYZ {
  final double x, y, z;
  const XYZ(this.x, this.y, this.z);
}

class ContourLine {
  final double elevation;
  final List<Pt> points;
  const ContourLine(this.elevation, this.points);
}

class Grid {
  final double x0, y0, cell;
  final int nx, ny;
  final List<List<double>> v; // v[j][i], NaN = tanpa data
  Grid(this.x0, this.y0, this.cell, this.nx, this.ny, this.v);
}

/// Interpolasi IDW ke grid. Sel yang terlalu jauh dari data diberi NaN.
Grid idwGrid(
  List<XYZ> pts, {
  required double cell,
  double power = 2,
  required double maxDist,
  int k = 12,
}) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final nx = ((maxX - minX) / cell).ceil() + 1;
  final ny = ((maxY - minY) / cell).ceil() + 1;
  final v = List.generate(ny, (_) => List<double>.filled(nx, double.nan));

  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      final gx = minX + i * cell, gy = minY + j * cell;
      final ds = <(double, XYZ)>[
        for (final p in pts)
          (math.sqrt(math.pow(p.x - gx, 2) + math.pow(p.y - gy, 2)).toDouble(), p)
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      if (ds.first.$1 > maxDist) continue;
      if (ds.first.$1 < 1e-9) {
        v[j][i] = ds.first.$2.z;
        continue;
      }
      var num = 0.0, den = 0.0;
      for (final e in ds.take(k)) {
        if (e.$1 > maxDist * 2) break;
        final w = 1 / math.pow(e.$1, power);
        num += w * e.$2.z;
        den += w;
      }
      v[j][i] = num / den;
    }
  }
  return Grid(minX, minY, cell, nx, ny, v);
}

/// Marching squares -> garis kontur untuk tiap level.
List<ContourLine> marchingSquares(Grid g, List<double> levels) {
  final out = <ContourLine>[];
  for (final lvl in levels) {
    final segs = <(Pt, Pt)>[];
    for (var j = 0; j < g.ny - 1; j++) {
      for (var i = 0; i < g.nx - 1; i++) {
        final v0 = g.v[j][i], v1 = g.v[j][i + 1];
        final v2 = g.v[j + 1][i + 1], v3 = g.v[j + 1][i];
        if (v0.isNaN || v1.isNaN || v2.isNaN || v3.isNaN) continue;
        final x0 = g.x0 + i * g.cell, y0 = g.y0 + j * g.cell;
        final x1 = x0 + g.cell, y1 = y0 + g.cell;

        double t(double a, double b) => (lvl - a) / (b - a);
        Pt e(int k) => switch (k) {
              0 => (x0 + t(v0, v1) * g.cell, y0),
              1 => (x1, y0 + t(v1, v2) * g.cell),
              2 => (x0 + t(v3, v2) * g.cell, y1),
              _ => (x0, y0 + t(v0, v3) * g.cell),
            };

        final idx = (v0 >= lvl ? 1 : 0) |
            (v1 >= lvl ? 2 : 0) |
            (v2 >= lvl ? 4 : 0) |
            (v3 >= lvl ? 8 : 0);
        void s(int a, int b) => segs.add((e(a), e(b)));
        switch (idx) {
          case 1:
          case 14:
            s(3, 0);
          case 2:
          case 13:
            s(0, 1);
          case 3:
          case 12:
            s(3, 1);
          case 4:
          case 11:
            s(1, 2);
          case 5:
            s(3, 0);
            s(1, 2);
          case 6:
          case 9:
            s(0, 2);
          case 7:
          case 8:
            s(3, 2);
          case 10:
            s(0, 1);
            s(2, 3);
        }
      }
    }
    for (final line in _join(segs)) {
      if (line.length >= 2) out.add(ContourLine(lvl, line));
    }
  }
  return out;
}

String _key(Pt p) => '${(p.$1 * 1000).round()}_${(p.$2 * 1000).round()}';

List<List<Pt>> _join(List<(Pt, Pt)> segs) {
  final byEnd = <String, List<int>>{};
  for (var i = 0; i < segs.length; i++) {
    byEnd.putIfAbsent(_key(segs[i].$1), () => []).add(i);
    byEnd.putIfAbsent(_key(segs[i].$2), () => []).add(i);
  }
  final used = List<bool>.filled(segs.length, false);
  final lines = <List<Pt>>[];

  int? nextAt(String key) {
    for (final i in byEnd[key] ?? const <int>[]) {
      if (!used[i]) return i;
    }
    return null;
  }

  for (var i = 0; i < segs.length; i++) {
    if (used[i]) continue;
    used[i] = true;
    final chain = <Pt>[segs[i].$1, segs[i].$2];
    // maju
    while (true) {
      final n = nextAt(_key(chain.last));
      if (n == null) break;
      used[n] = true;
      final s = segs[n];
      chain.add(_key(s.$1) == _key(chain.last) ? s.$2 : s.$1);
    }
    // mundur
    while (true) {
      final n = nextAt(_key(chain.first));
      if (n == null) break;
      used[n] = true;
      final s = segs[n];
      chain.insert(0, _key(s.$1) == _key(chain.first) ? s.$2 : s.$1);
    }
    lines.add(chain);
  }
  return lines;
}

/// Penghalusan Chaikin (opsional, 1-2 iterasi cukup).
List<Pt> chaikin(List<Pt> p, {int iterations = 1}) {
  var cur = p;
  for (var it = 0; it < iterations; it++) {
    if (cur.length < 3) return cur;
    final n = <Pt>[cur.first];
    for (var i = 0; i < cur.length - 1; i++) {
      final a = cur[i], b = cur[i + 1];
      n.add((0.75 * a.$1 + 0.25 * b.$1, 0.75 * a.$2 + 0.25 * b.$2));
      n.add((0.25 * a.$1 + 0.75 * b.$1, 0.25 * a.$2 + 0.75 * b.$2));
    }
    n.add(cur.last);
    cur = n;
  }
  return cur;
}

/// Pipeline lengkap: titik -> grid IDW -> kontur pada kelipatan [interval].
List<ContourLine> buildContours(List<XYZ> pts, double interval, {int smooth = 1}) {
  if (pts.length < 4) return [];
  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  var minZ = double.infinity, maxZ = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
    minZ = math.min(minZ, p.z);
    maxZ = math.max(maxZ, p.z);
  }
  final span = math.max(maxX - minX, maxY - minY);
  if (span < 1) return [];
  final cell = math.max(span / 150, 0.5);
  final grid = idwGrid(pts, cell: cell, maxDist: math.max(span * 0.25, cell * 4));

  final levels = <double>[];
  for (var l = (minZ / interval).ceil() * interval; l <= maxZ; l += interval) {
    levels.add(l);
  }
  final lines = marchingSquares(grid, levels);
  return smooth <= 0
      ? lines
      : [for (final l in lines) ContourLine(l.elevation, chaikin(l.points, iterations: smooth))];
}
