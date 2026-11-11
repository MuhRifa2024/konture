import 'dart:math' as math;

class Sample {
  final double lat, lon, alt, accuracy, tMs;
  final double? pressure;
  const Sample({
    required this.lat,
    required this.lon,
    required this.alt,
    required this.accuracy,
    required this.tMs,
    this.pressure,
  });
}

class AveragedPoint {
  final double lat, lon, alt, meanAccuracy, stdH, tMs;
  final double? pressure;
  final int nUsed, nTotal;
  const AveragedPoint({
    required this.lat,
    required this.lon,
    required this.alt,
    required this.meanAccuracy,
    required this.stdH,
    required this.tMs,
    required this.pressure,
    required this.nUsed,
    required this.nTotal,
  });
}

double _median(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Rata-rata sampel titik henti dengan penolakan outlier (median + MAD).
AveragedPoint? averageSamples(List<Sample> samples, {double madK = 3.5}) {
  if (samples.length < 3) return null;
  final mLat = _median(samples.map((s) => s.lat).toList());
  final mLon = _median(samples.map((s) => s.lon).toList());
  const kLat = 111320.0;
  final kLon = 111320.0 * math.cos(mLat * math.pi / 180);

  double dist(Sample s) => math.sqrt(
      math.pow((s.lat - mLat) * kLat, 2) + math.pow((s.lon - mLon) * kLon, 2));

  final d = samples.map(dist).toList();
  final med = _median(d);
  final mad = _median(d.map((e) => (e - med).abs()).toList());
  final limit = med + madK * 1.4826 * math.max(mad, 0.3);

  final kept = <Sample>[
    for (var i = 0; i < samples.length; i++)
      if (d[i] <= limit) samples[i]
  ];
  if (kept.length < 3) return null;

  double mean(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;
  final lat = mean(kept.map((s) => s.lat));
  final lon = mean(kept.map((s) => s.lon));
  final press =
      kept.where((s) => s.pressure != null).map((s) => s.pressure!).toList();

  final varH = mean(kept.map((s) =>
      math.pow((s.lat - lat) * kLat, 2).toDouble() +
      math.pow((s.lon - lon) * kLon, 2).toDouble()));

  return AveragedPoint(
    lat: lat,
    lon: lon,
    alt: mean(kept.map((s) => s.alt)),
    meanAccuracy: mean(kept.map((s) => s.accuracy)),
    stdH: math.sqrt(varH),
    tMs: mean(kept.map((s) => s.tMs)),
    pressure: press.isEmpty ? null : mean(press),
    nUsed: kept.length,
    nTotal: samples.length,
  );
}
