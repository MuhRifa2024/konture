import 'package:flutter/material.dart';
import '../ble/base_sync_client.dart';
import '../ble/rtk_receiver.dart';
import '../data/app_state.dart';
import '../data/models.dart';

class BleTab extends StatefulWidget {
  final AppState s;
  const BleTab(this.s, {super.key});
  @override
  State<BleTab> createState() => _BleTabState();
}

class _BleTabState extends State<BleTab> {
  bool scanningBase = false;
  bool scanningRtk = false;
  bool busy = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  void dispose() {
    widget.s.syncClient.stopScan();
    widget.s.rtk.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Sinkronisasi Base ↔ Rover (BLE)', style: th.titleMedium),
      const SizedBox(height: 4),
      const Text('Dekatkan Rover ke Base (di bawah ±20 m) saat sinkronisasi. '
          'Jaraknya terbatas, jadi lakukan di awal atau akhir survei.'),
      const SizedBox(height: 8),
      if (s.role == Role.base) _baseSection(s) else _roverSection(s),
      const Divider(height: 32),
      Text('Receiver RTK/GNSS eksternal (BLE)', style: th.titleMedium),
      const SizedBox(height: 4),
      const Text('Receiver harus mengirim NMEA (GGA) lewat BLE. '
          'Receiver yang hanya Bluetooth Classic (SPP) tidak akan muncul.'),
      const SizedBox(height: 8),
      _rtkSection(s),
    ]);
  }

  Widget _baseSection(AppState s) {
    return Card(
      child: Column(children: [
        SwitchListTile(
          title: const Text('Siarkan log Base via BLE'),
          subtitle: ValueListenableBuilder<String>(
            valueListenable: s.baseServer.status,
            builder: (_, v, __) => Text('$v • ${s.ownPressureLog.length} entri tekanan'),
          ),
          value: s.baseServer.running,
          onChanged: (v) async {
            final err = await s.toggleBaseBroadcast(v);
            if (err != null) _snack(err);
            setState(() {});
          },
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('Biarkan aplikasi terbuka dan layar menyala di HP Base.'),
        ),
      ]),
    );
  }

  Widget _roverSection(AppState s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FilledButton.icon(
        icon: Icon(scanningBase ? Icons.stop : Icons.bluetooth_searching),
        label: Text(scanningBase ? 'Berhenti mencari' : 'Cari HP Base'),
        onPressed: () async {
          if (scanningBase) {
            await s.syncClient.stopScan();
            setState(() => scanningBase = false);
            return;
          }
          final err = await s.syncClient.startScan();
          if (err != null) {
            _snack(err);
          } else {
            setState(() => scanningBase = true);
          }
        },
      ),
      ValueListenableBuilder<String>(
        valueListenable: s.syncClient.status,
        builder: (_, v, __) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(v)),
      ),
      ValueListenableBuilder<List<BaseCandidate>>(
        valueListenable: s.syncClient.found,
        builder: (_, list, __) => Column(children: [
          for (final c in list)
            Card(
              child: ListTile(
                leading: const Icon(Icons.sensors),
                title: Text(c.name),
                subtitle: Text('RSSI ${c.rssi} dBm'),
                trailing: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          final m = await s.fetchBase(c);
                          if (mounted) setState(() => busy = false);
                          _snack(m);
                        },
                  child: const Text('Ambil log'),
                ),
              ),
            ),
        ]),
      ),
      if (s.importedBaseLog.isNotEmpty)
        Text('Log Base tersimpan: ${s.importedBaseLog.length} entri, elevasi Base ${s.baseZ.toStringAsFixed(2)} m'),
    ]);
  }

  Widget _rtkSection(AppState s) {
    return ListenableBuilder(
      listenable: Listenable.merge([s.rtk.latest, s.rtk.status]),
      builder: (_, __) {
        final fix = s.rtk.latest.value;
        if (s.rtk.connected) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Terhubung: ${s.rtk.connectedName ?? ''}'),
                Text(s.rtk.status.value),
                if (fix != null) ...[
                  const SizedBox(height: 6),
                  Text('Status: ${fix.qualityLabel}'),
                  Text('Satelit: ${fix.satellites}   HDOP: ${fix.hdop}'),
                  Text('Lat: ${fix.lat.toStringAsFixed(8)}'),
                  Text('Lon: ${fix.lon.toStringAsFixed(8)}'),
                  Text('Tinggi (MSL): ${fix.altitude.toStringAsFixed(3)} m'),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pakai RTK untuk Ukur titik'),
                  subtitle: const Text('Posisi dan tinggi diambil dari receiver, bukan dari GPS HP'),
                  value: s.useRtk,
                  onChanged: (v) {
                    s.useRtk = v;
                    s.refresh();
                    setState(() {});
                  },
                ),
                OutlinedButton(
                  onPressed: () async {
                    await s.rtk.disconnect();
                    s.useRtk = false;
                    s.refresh();
                    setState(() {});
                  },
                  child: const Text('Putuskan'),
                ),
              ]),
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FilledButton.icon(
            icon: Icon(scanningRtk ? Icons.stop : Icons.bluetooth_searching),
            label: Text(scanningRtk ? 'Berhenti mencari' : 'Cari receiver'),
            onPressed: () async {
              if (scanningRtk) {
                await s.rtk.stopScan();
                setState(() => scanningRtk = false);
                return;
              }
              final err = await s.rtk.startScan();
              if (err != null) {
                _snack(err);
              } else {
                setState(() => scanningRtk = true);
              }
            },
          ),
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(s.rtk.status.value)),
          ValueListenableBuilder<List<RtkDevice>>(
            valueListenable: s.rtk.found,
            builder: (_, list, __) => Column(children: [
              for (final d in list)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.satellite_alt),
                    title: Text(d.name),
                    subtitle: Text('RSSI ${d.rssi} dBm'),
                    trailing: FilledButton(
                      onPressed: () async {
                        final err = await s.rtk.connectDevice(d);
                        if (err != null) _snack(err);
                        if (mounted) setState(() => scanningRtk = false);
                      },
                      child: const Text('Hubungkan'),
                    ),
                  ),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}
