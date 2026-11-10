import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../contour/contour.dart';
import '../data/app_state.dart';
import '../data/models.dart';

class HomePage extends StatefulWidget {
  final AppState state;
  const HomePage({super.key, required this.state});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final pages = [MeasureTab(s), PointsTab(s), ContourTab(s), ExportTab(s)];
    return Scaffold(
      appBar: AppBar(title: const Text('KonturSurvey')),
      body: ListenableBuilder(listenable: s, builder: (_, __) => pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.gps_fixed), label: 'Ukur'),
          NavigationDestination(icon: Icon(Icons.list), label: 'Titik'),
          NavigationDestination(icon: Icon(Icons.terrain), label: 'Kontur'),
          NavigationDestination(icon: Icon(Icons.ios_share), label: 'Ekspor'),
        ],
      ),
    );
  }
}

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

// ---------------- Tab Ukur ----------------
class MeasureTab extends StatefulWidget {
  final AppState s;
  const MeasureTab(this.s, {super.key});
  @override
  State<MeasureTab> createState() => _MeasureTabState();
}

class _MeasureTabState extends State<MeasureTab> {
  final name = TextEditingController();
  double progress = 0;
  bool busy = false;
  int seconds = 45;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (s.sensorError != null)
        Card(color: Colors.red.shade100, child: ListTile(title: Text(s.sensorError!))),
      SegmentedButton<Role>(
        segments: const [
          ButtonSegment(value: Role.standalone, label: Text('Mandiri')),
          ButtonSegment(value: Role.base, label: Text('Base')),
          ButtonSegment(value: Role.rover, label: Text('Rover')),
        ],
        selected: {s.role},
        onSelectionChanged: (v) => s.setRole(v.first),
      ),
      const SizedBox(height: 12),
      ValueListenableBuilder(
        valueListenable: s.sensors.position,
        builder: (_, pos, __) => ValueListenableBuilder(
          valueListenable: s.sensors.pressure,
          builder: (_, pr, __) => Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Lat: ${pos?.latitude.toStringAsFixed(7) ?? '-'}'),
                Text('Lon: ${pos?.longitude.toStringAsFixed(7) ?? '-'}'),
                Text('Akurasi HP: ±${pos?.accuracy.toStringAsFixed(1) ?? '-'} m'),
                Text('Altitude GNSS: ${pos?.altitude.toStringAsFixed(1) ?? '-'} m (tidak untuk kontur)'),
                Text('Tekanan: ${pr?.toStringAsFixed(2) ?? 'tidak ada barometer'} hPa'),
                Text('Titik tersimpan: ${s.points.length}'),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (s.role == Role.base)
        const Card(
          child: ListTile(
            leading: Icon(Icons.sensors),
            title: Text('Base aktif: mencatat tekanan tiap 5 detik'),
            subtitle: Text('Letakkan diam di titik stabil, lalu ekspor sesi di tab Ekspor.'),
          ),
        )
      else ...[
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama titik (opsional)')),
        Row(children: [
          const Text('Durasi: '),
          Expanded(
            child: Slider(
              min: 20,
              max: 90,
              divisions: 7,
              value: seconds.toDouble(),
              label: '$seconds dtk',
              onChanged: busy ? null : (v) => setState(() => seconds = v.round()),
            ),
          ),
          Text('$seconds dtk'),
        ]),
        FilledButton.icon(
          icon: const Icon(Icons.place),
          label: Text(busy ? 'Mengukur... jangan bergerak' : 'Ukur titik'),
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    progress = 0;
                  });
                  final msg = await s.measure(name.text, Duration(seconds: seconds), (p) {
                    if (mounted) setState(() => progress = p);
                  });
                  if (!mounted) return;
                  setState(() => busy = false);
                  name.clear();
                  _snack(context, msg);
                },
        ),
        if (busy) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(value: progress)),
      ],
    ]);
  }
}

// ---------------- Tab Titik ----------------
class PointsTab extends StatelessWidget {
  final AppState s;
  const PointsTab(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController(text: s.baseZ.toString());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(
              labelText: 'Elevasi titik Base (m, dari BM/DEM)', border: OutlineInputBorder()),
          onSubmitted: (v) {
            s.baseZ = double.tryParse(v) ?? s.baseZ;
            s.save();
            s.refresh();
          },
        ),
      ),
      Expanded(
        child: ListView(children: [
          for (final p in s.points.reversed)
            () {
              final (z, m) = s.elevationOf(p);
              final color = switch (p.qa) { 'baik' => Colors.green, 'cukup' => Colors.orange, _ => Colors.red };
              return ListTile(
                leading: CircleAvatar(backgroundColor: color, radius: 8),
                title: Text('${p.name}  •  Z ${z.toStringAsFixed(2)} m'),
                subtitle: Text('${p.id} • $m • ±${p.accuracy.toStringAsFixed(1)} m • ${p.nUsed} sampel'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => s.removePoint(p.id)),
              );
            }(),
        ]),
      ),
    ]);
  }
}

// ---------------- Tab Kontur ----------------
class ContourTab extends StatelessWidget {
  final AppState s;
  const ContourTab(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Text('Interval: '),
        DropdownButton<double>(
          value: s.interval,
          items: [for (final v in [0.5, 1.0, 2.0, 5.0, 10.0]) DropdownMenuItem(value: v, child: Text('$v m'))],
          onChanged: (v) {
            s.interval = v ?? s.interval;
            s.refresh();
          },
        ),
        const Spacer(),
        FilledButton(onPressed: s.computeContours, child: const Text('Hitung kontur')),
      ]),
      const SizedBox(height: 12),
      Container(
        height: 360,
        decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
        child: s.contours.isEmpty
            ? const Center(child: Text('Belum ada kontur (butuh ≥4 titik kualitas baik/cukup)'))
            : CustomPaint(painter: _ContourPainter(s.contours), size: Size.infinite),
      ),
      const SizedBox(height: 8),
      Text('${s.contours.length} garis kontur'),
    ]);
  }
}

class _ContourPainter extends CustomPainter {
  final List<ContourLine> lines;
  _ContourPainter(this.lines);
  @override
  void paint(Canvas canvas, Size size) {
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    var minZ = double.infinity, maxZ = -double.infinity;
    for (final l in lines) {
      minZ = l.elevation < minZ ? l.elevation : minZ;
      maxZ = l.elevation > maxZ ? l.elevation : maxZ;
      for (final p in l.points) {
        minX = p.$1 < minX ? p.$1 : minX;
        maxX = p.$1 > maxX ? p.$1 : maxX;
        minY = p.$2 < minY ? p.$2 : minY;
        maxY = p.$2 > maxY ? p.$2 : maxY;
      }
    }
    const pad = 12.0;
    final sc = ((size.width - 2 * pad) / (maxX - minX + 1e-9))
        .clamp(0, (size.height - 2 * pad) / (maxY - minY + 1e-9))
        .toDouble();
    Offset map((double, double) p) => Offset(pad + (p.$1 - minX) * sc, size.height - pad - (p.$2 - minY) * sc);
    for (final l in lines) {
      final t = maxZ == minZ ? 0.5 : (l.elevation - minZ) / (maxZ - minZ);
      final paint = Paint()
        ..color = Color.lerp(Colors.green.shade700, Colors.brown.shade700, t)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final path = Path()..moveTo(map(l.points.first).dx, map(l.points.first).dy);
      for (final p in l.points.skip(1)) {
        path.lineTo(map(p).dx, map(p).dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ContourPainter old) => old.lines != lines;
}

// ---------------- Tab Ekspor ----------------
class ExportTab extends StatelessWidget {
  final AppState s;
  const ExportTab(this.s, {super.key});

  Future<void> _share(BuildContext c, String fileName, Object json) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$fileName');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    await Share.shareXFiles([XFile(f.path)]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('GeoJSON lama: ${s.oldGeoJsonName ?? '(belum dimuat)'}'),
      OutlinedButton.icon(
        icon: const Icon(Icons.upload_file),
        label: const Text('Impor GeoJSON lama'),
        onPressed: () async {
          final r = await FilePicker.platform.pickFiles();
          final path = r?.files.single.path;
          if (path == null) return;
          s.oldGeoJson = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
          s.oldGeoJsonName = r!.files.single.name;
          s.refresh();
        },
      ),
      const Divider(height: 32),
      FilledButton.icon(
        icon: const Icon(Icons.save_alt),
        label: Text(s.oldGeoJson == null ? 'Ekspor GeoJSON baru' : 'Ekspor hasil merge (file baru)'),
        onPressed: () => _share(context, 'survey_${DateTime.now().millisecondsSinceEpoch}.geojson', s.buildExport()),
      ),
      const Divider(height: 32),
      const Text('Sinkronisasi Base ↔ Rover'),
      OutlinedButton.icon(
        icon: const Icon(Icons.share),
        label: const Text('Ekspor sesi Base (log tekanan)'),
        onPressed: () => _share(context, 'base_session.json', s.buildBaseSession()),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.download),
        label: const Text('Impor sesi Base'),
        onPressed: () async {
          final r = await FilePicker.platform.pickFiles();
          final path = r?.files.single.path;
          if (path == null) return;
          s.importBaseSession(jsonDecode(await File(path).readAsString()) as Map<String, dynamic>);
          if (context.mounted) _snack(context, 'Log Base dimuat (${s.importedBaseLog.length} entri)');
        },
      ),
    ]);
  }
}
