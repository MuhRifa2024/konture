import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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
  final List<SurveyPoint> points = [];
  final List<List<double>> ownPressureLog = []; // dicatat saat peran Base
  List<List<double>> importedBaseLog = []; // log dari HP Base
  Role role = Role.standalone;
  double baseZ = 0; // elevasi referensi titik Base (m)
  double interval = 5;
  Map<String, dynamic>? oldGeoJson;
  String? oldGeoJsonName;
  List<ContourLine> contours = [];
  UtmConverter? utm;
  String? sensorError;
  Timer? _baseTimer;
  bool _started = false;

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

  void refresh() => notifyListeners();

  bool get baseLogging => role == Role.base;

  Future<String> measure(String name, Duration d, void Function(double) onProgress) async {
    final samples = await sensors.collect(d, onProgress);
    final avg = averageSamples(samples);
    if (avg == null) return 'Sampel tidak cukup (${samples.length}). Pastikan GPS sudah fix.';
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
    ));
    await save();
    notifyListeners();
    return 'Tersimpan (${avg.nUsed}/${avg.nTotal} sampel, akurasi ±${avg.meanAccuracy.toStringAsFixed(1)} m, ${qa.name})';
  }

  void removePoint(String id) {
    points.removeWhere((p) => p.id == id);
    save();
    notifyListeners();
  }

  /// Elevasi titik. Dengan log Base: Z = baseZ + beda tinggi barometrik.
  /// Tanpa log Base: jatuh ke altitude GNSS (kurang akurat).
  (double, String) elevationOf(SurveyPoint p) {
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

  /// FeatureCollection baru (titik + kontur), digabung ke GeoJSON lama jika ada.
  Map<String, dynamic> buildExport() {
    final feats = <Map<String, dynamic>>[
      for (final p in points)
        () {
          final (z, m) = elevationOf(p);
          return pointFeature(id: p.id, lat: p.lat, lon: p.lon, z: z, props: {
            'name': p.name,
            'method': m,
            'accuracy_m': double.parse(p.accuracy.toStringAsFixed(2)),
            'std_h_m': double.parse(p.stdH.toStringAsFixed(2)),
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
    return oldGeoJson == null
        ? featureCollection(feats)
        : mergeGeoJson(oldGeoJson!, feats);
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

  // ---- persistensi sederhana (JSON). Ganti ke SQLite/drift bila perlu. ----
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
    } catch (_) {
      // berkas rusak: abaikan, mulai kosong
    }
  }
}
