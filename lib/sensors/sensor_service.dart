import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../survey/point_averager.dart';

/// GNSS + barometer. Berjalan sebagai foreground service agar tetap
/// merekam saat layar mati.
class SensorService {
  final ValueNotifier<Position?> position = ValueNotifier(null);
  final ValueNotifier<double?> pressure = ValueNotifier(null);
  final List<void Function(Position)> _listeners = [];
  StreamSubscription<Position>? _ps;
  StreamSubscription<BarometerEvent>? _bs;

  /// Mengembalikan pesan galat, atau null jika berhasil.
  Future<String?> start() async {
    if (!await Geolocator.isLocationServiceEnabled()) return 'GPS belum aktif';
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return 'Izin lokasi ditolak';
    }
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'KonturSurvey',
        notificationText: 'Merekam data survei',
        enableWakeLock: true,
      ),
    );
    _ps = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      position.value = p;
      for (final l in List.of(_listeners)) {
        l(p);
      }
    });
    _bs = barometerEventStream().listen(
      (e) => pressure.value = e.pressure,
      onError: (_) {},
    );
    return null;
  }

  Future<void> stop() async {
    await _ps?.cancel();
    await _bs?.cancel();
  }

  /// Mengumpulkan sampel selama [duration] (titik henti).
  Future<List<Sample>> collect(
    Duration duration,
    void Function(double progress) onProgress,
  ) async {
    final samples = <Sample>[];
    void l(Position p) {
      samples.add(Sample(
        lat: p.latitude,
        lon: p.longitude,
        alt: p.altitude,
        accuracy: p.accuracy,
        pressure: pressure.value,
        tMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      ));
    }

    _listeners.add(l);
    final start = DateTime.now();
    while (true) {
      final el = DateTime.now().difference(start);
      onProgress((el.inMilliseconds / duration.inMilliseconds).clamp(0, 1).toDouble());
      if (el >= duration) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _listeners.remove(l);
    return samples;
  }
}
