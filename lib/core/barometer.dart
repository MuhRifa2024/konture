import 'dart:math' as math;

/// Beda tinggi rover terhadap base (m) dari selisih tekanan (hPa),
/// memakai rumus hipsometrik. Positif = rover lebih tinggi dari base.
double heightDifference({
  required double pBase,
  required double pRover,
  double tempC = 15,
}) {
  const r = 287.05; // J/(kg K)
  const g = 9.80665;
  final t = tempC + 273.15;
  return (r * t / g) * math.log(pBase / pRover);
}

/// Log tekanan base [waktu ms, hPa], diinterpolasi linear.
class PressureLog {
  final List<List<double>> entries; // [tMs, hPa], terurut waktu
  PressureLog(this.entries);

  bool get isEmpty => entries.isEmpty;

  /// Tekanan pada waktu [tMs]; null jika di luar rentang + [toleranceMs].
  double? at(double tMs, {double toleranceMs = 60000}) {
    if (entries.isEmpty) return null;
    if (tMs < entries.first[0] - toleranceMs || tMs > entries.last[0] + toleranceMs) {
      return null;
    }
    if (tMs <= entries.first[0]) return entries.first[1];
    if (tMs >= entries.last[0]) return entries.last[1];
    var lo = 0, hi = entries.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (entries[mid][0] <= tMs) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = entries[lo], b = entries[hi];
    final f = (tMs - a[0]) / (b[0] - a[0]);
    return a[1] + f * (b[1] - a[1]);
  }
}
