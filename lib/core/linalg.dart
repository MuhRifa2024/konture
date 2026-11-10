/// Penyelesai sistem linear kecil (eliminasi Gauss, pivot parsial).
/// Mengembalikan null jika matriks singular.
List<double>? solveLinear(List<List<double>> a, List<double> b) {
  final n = b.length;
  final m = [
    for (var i = 0; i < n; i++) [...a[i], b[i]]
  ];
  for (var c = 0; c < n; c++) {
    var p = c;
    for (var r = c + 1; r < n; r++) {
      if (m[r][c].abs() > m[p][c].abs()) p = r;
    }
    if (m[p][c].abs() < 1e-12) return null;
    final t = m[c];
    m[c] = m[p];
    m[p] = t;
    for (var r = c + 1; r < n; r++) {
      final f = m[r][c] / m[c][c];
      for (var k = c; k <= n; k++) {
        m[r][k] -= f * m[c][k];
      }
    }
  }
  final x = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var s = m[i][n];
    for (var j = i + 1; j < n; j++) {
      s -= m[i][j] * x[j];
    }
    x[i] = s / m[i][i];
  }
  return x;
}
