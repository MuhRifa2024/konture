import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../ble/base_sync_client.dart';
import '../ble/base_sync_server.dart';
import '../ble/rtk_receiver.dart';
import '../ble/sync_protocol.dart';
import '../contour/contour.dart';
import '../core/barometer.dart';
import '../core/geo_utils.dart';
import '../sensors/sensor_service.dart';
import '../survey/point_averager.dart';
import '../survey/qa.dart';
import 'geojson_io.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  final sensors = SensorService();
  final rtk = RtkReceiver();
  final syncClient = BaseSyncClient();
  late final BaseSyncServer baseServer =
      BaseSyncServer(provider: () => BaseSession(baseZ, ownPressureLog));

  final List<SurveyPoint> points = [];
  final List<List<double>> ownPressureLog = []; // dicatat saat peran Base
  List<List<double>> importedBaseLog = []; // log dari HP Base
  Role role = Role.standalone;
  double baseZ = 0; // elevasi referensi titik Base (m)
  double interval = 5;
  bool useRtk = false;
  Map<String, dynamic>? oldGeoJson;
  String? oldGeoJsonName;
  List<ContourLine> contours = [];
  UtmConverter? utm;
  String? sensorError;
  Timer? _baseTimer;
  bool _started = false;

  void refresh() => notifyListeners();

  Future<void> init() async {
    if (_started) return;
    _started = true;
    await _load();
    sensorError = await sensors.start();
    notifyListeners();
  }

  void setRole(Role r) {
    role = r;
    _baseTimer?.cancel();
    if (r != Role.base && baseServer.running) baseServer.stop();
    if (r == Role.base) {
      _baseTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        final p = sensors.pressure.value;
        if (p != null) {
          ownPressureLog.add([DateTime.now().millisecondsSinceEpoch.toDouble(), p]);
          save();
        }
      });
    }
    notifyListeners();
  }

  bool get baseLogging => role == Role.base;

  /// Menyalakan/mematikan siaran BLE log Base. Mengembalikan pesan galat atau null.
  Future<String?> toggleBaseBroadcast(bool on) async {
    if (on) return baseServer.start();
    await baseServer.stop();
    return null;
  }

  /// Rover: unduh log Base lewat BLE dan terapkan.
  Future<String> fetchBase(BaseCandidate c) async {
    try {
      final s = await syncClient.fetch(c.peripheral);
      importBaseSession({'baseZ': s.baseZ, 'baseLog': s.log});
      return 'Log Base diterima: ${s.log.length} entri, elevasi Base ${s.baseZ.toStringAsFixed(2)} m';
    } catch (e) {
      syncClient.status.value = 'Gagal';
      return 'Gagal sinkronisasi: $e';
    }
  }

  Future<List<Sample>> _collectRtk(
    Duration d,
    void Function(double) onProgress,
    List<int> qualities,
  ) async {
    final out = <Sample>[];
    final sub = rtk.fixes.listen((f) {
      if (f.quality == 0) return;
      final gst = rtk.latestGst.value;
      final acc = gst != null
          ? math.sqrt(gst.stdLat * gst.stdLat + gst.stdLon * gst.stdLon)
          : switch (f.quality) { 4 => 0.03, 5 => 0.5, _ => f.hdop * 2.5 };
      out.add(Sample(
        lat: f.lat,
        lon: f.lon,
        alt: f.altitude,
        accuracy: acc,
        tMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        pressure: sensors.pressure.value,
      ));
      qualities.add(f.quality);
    });
    final start = DateTime.now();
    while (true) {
      final el = DateTime.now().difference(start);
      onProgress((el.inMilliseconds / d.inMilliseconds).clamp(0, 1).toDouble());
      if (el >= d) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await sub.cancel();
    return out;
  }

  Future<String> measure(String name, Duration d, void Function(double) onProgress) async {
    final rtkMode = useRtk && rtk.connected && rtk.latest.value != null;
    final qualities = <int>[];
    final samples = rtkMode
        ? await _collectRtk(d, onProgress, qualities)
        : await sensors.collect(d, onProgress);
    final avg = averageSamples(samples);
    if (avg == null) {
      return 'Sampel tidak cukup (${samples.length}). Pastikan ${rtkMode ? 'receiver RTK mengirim data' : 'GPS sudah fix'}.';
    }

    var rtkQ = 0;
    if (rtkMode && qualities.isNotEmpty) {
      final fixed = qualities.where((q) => q == 4).length / qualities.length;
      if (fixed >= 0.9) {
        rtkQ = 4;
      } else if (qualities.every((q) => q == 4 || q == 5)) {
        rtkQ = 5;
      } else {
        rtkQ = 1;
      }
    }

    final qa = assessPoint(meanAccuracy: avg.meanAccuracy, stdH: avg.stdH, nUsed: avg.nUsed);
    points.add(SurveyPoint(
      id: 'SRV-${(points.length + 1).toString().padLeft(4, '0')}',
      name: name.isEmpty ? 'Titik ${points.length + 1}' : name,
      lat: avg.lat,
      lon: avg.lon,
      gnssAlt: avg.alt,
      accuracy: avg.meanAccuracy,
      stdH: avg.stdH,
      tMs: avg.tMs,
      pressure: avg.pressure,
      nUsed: avg.nUsed,
      qa: qa.name,
      source: rtkMode ? 'rtk' : 'phone',
      rtkQuality: rtkQ,
    ));
    await save();
    notifyListeners();
    final src = rtkMode ? 'RTK ${rtkQ == 4 ? 'fixed' : rtkQ == 5 ? 'float' : 'non-RTK'}' : 'HP';
    return 'Tersimpan [$src] (${avg.nUsed}/${avg.nTotal} sampel, ±${avg.meanAccuracy.toStringAsFixed(2)} m, ${qa.name})';
  }

  void removePoint(String id) {
    points.removeWhere((p) => p.id == id);
    save();
    notifyListeners();
  }

  /// Elevasi titik:
  /// 1) RTK fixed/float -> altitude receiver (MSL).
  /// 2) Ada log Base + tekanan -> Z = baseZ + beda tinggi barometrik.
  /// 3) Selain itu -> altitude GNSS HP (kurang akurat).
  (double, String) elevationOf(SurveyPoint p) {
    if (p.source == 'rtk' && (p.rtkQuality == 4 || p.rtkQuality == 5)) {
      return (p.gnssAlt, p.rtkQuality == 4 ? 'rtk-fixed' : 'rtk-float');
    }
    final log = PressureLog(importedBaseLog.isNotEmpty ? importedBaseLog : ownPressureLog);
    final pb = log.at(p.tMs);
    if (pb != null && p.pressure != null) {
      return (baseZ + heightDifference(pBase: pb, pRover: p.pressure!), 'barometer+base');
    }
    return (p.gnssAlt, 'gnss');
  }

  void computeContours() {
    final usable = points.where((p) => p.qa != 'buruk').toList();
    if (usable.length < 4) {
      contours = [];
      notifyListeners();
      return;
    }
    utm = UtmConverter.forLocation(usable.first.lat, usable.first.lon);
    final xyz = [
      for (final p in usable)
        () {
          final (e, n) = utm!.toUtm(p.lat, p.lon);
          return XYZ(e, n, elevationOf(p).$1);
        }()
    ];
    contours = buildContours(xyz, interval);
    notifyListeners();
  }

  Map<String, dynamic> buildExport() {
    final feats = <Map<String, dynamic>>[
      for (final p in points)
        () {
          final (z, m) = elevationOf(p);
          return pointFeature(id: p.id, lat: p.lat, lon: p.lon, z: z, props: {
            'name': p.name,
            'method': m,
            'gnss_source': p.source,
            'accuracy_m': double.parse(p.accuracy.toStringAsFixed(3)),
            'std_h_m': double.parse(p.stdH.toStringAsFixed(3)),
            'n_samples': p.nUsed,
            'qa': p.qa,
            'surveyed_at': DateTime.fromMillisecondsSinceEpoch(p.tMs.round(), isUtc: true).toIso8601String(),
            'source': 'survey',
          });
        }()
    ];
    if (utm != null && contours.isNotEmpty) {
      feats.addAll(contourFeatures(contours, utm!, interval: interval));
    }
    return oldGeoJson == null ? featureCollection(feats) : mergeGeoJson(oldGeoJson!, feats);
  }

  Map<String, dynamic> buildBaseSession() => {
        'type': 'kontur_base_session',
        'baseZ': baseZ,
        'baseLog': ownPressureLog,
      };

  void importBaseSession(Map<String, dynamic> j) {
    importedBaseLog = [
      for (final e in (j['baseLog'] as List)) [(e[0] as num).toDouble(), (e[1] as num).toDouble()]
    ]..sort((a, b) => a[0].compareTo(b[0]));
    if (j['baseZ'] != null) baseZ = (j['baseZ'] as num).toDouble();
    save();
    notifyListeners();
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/project.json');
  }

  Future<void> save() async {
    final f = await _file();
    await f.writeAsString(jsonEncode({
      'points': points.map((p) => p.toJson()).toList(),
      'ownPressureLog': ownPressureLog,
      'importedBaseLog': importedBaseLog,
      'baseZ': baseZ,
      'interval': interval,
    }));
  }

  Future<void> _load() async {
    final f = await _file();
    if (!await f.exists()) return;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      points
        ..clear()
        ..addAll((j['points'] as List).map((e) => SurveyPoint.fromJson(e as Map<String, dynamic>)));
      List<List<double>> toLog(dynamic v) => [
            for (final e in (v as List? ?? const []))
              [(e[0] as num).toDouble(), (e[1] as num).toDouble()]
          ];
      ownPressureLog
        ..clear()
        ..addAll(toLog(j['ownPressureLog']));
      importedBaseLog = toLog(j['importedBaseLog']);
      baseZ = (j['baseZ'] as num?)?.toDouble() ?? 0;
      interval = (j['interval'] as num?)?.toDouble() ?? 5;
    } catch (_) {}
  }
}
