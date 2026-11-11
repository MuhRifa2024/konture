import 'dart:async';
import 'dart:convert';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import '../sensors/nmea_parser.dart';
import 'ble_common.dart';

class RtkDevice {
  final Peripheral peripheral;
  final String name;
  final int rssi;
  const RtkDevice(this.peripheral, this.name, this.rssi);
}

/// Menerima NMEA (GGA/GST) dari receiver GNSS/RTK lewat BLE.
/// Berlangganan ke semua karakteristik notify yang ada (kompatibel dengan
/// Nordic UART, HM-10/FFE1, dan modul serupa), lalu mengurai kalimat NMEA.
/// Receiver yang hanya mendukung Bluetooth Classic (SPP) tidak terdeteksi.
class RtkReceiver {
  final CentralManager _cm = CentralManager();
  final ValueNotifier<List<RtkDevice>> found = ValueNotifier([]);
  final ValueNotifier<GgaFix?> latest = ValueNotifier(null);
  final ValueNotifier<GstError?> latestGst = ValueNotifier(null);
  final ValueNotifier<String> status = ValueNotifier('Belum terhubung');
  final _fixCtrl = StreamController<GgaFix>.broadcast();
  final Map<String, NmeaLineBuffer> _buffers = {};
  StreamSubscription<DiscoveredEventArgs>? _dSub;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>? _nSub;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>? _cSub;
  Peripheral? _connected;
  String? connectedName;

  Stream<GgaFix> get fixes => _fixCtrl.stream;
  bool get connected => _connected != null;

  Future<String?> startScan() async {
    final err = await ensureBluetoothReady();
    if (err != null) return err;
    found.value = [];
    await _dSub?.cancel();
    _dSub = _cm.discovered.listen((e) {
      final name = e.advertisement.name;
      if (name == null || name.isEmpty || name == 'KonturBase') return;
      final dev = RtkDevice(e.peripheral, name, e.rssi);
      final list = [...found.value];
      final i = list.indexWhere((d) => d.peripheral.uuid == e.peripheral.uuid);
      if (i >= 0) {
        list[i] = dev;
      } else {
        list.add(dev);
      }
      found.value = list;
    });
    await _cm.startDiscovery();
    return null;
  }

  Future<void> stopScan() async {
    await _dSub?.cancel();
    _dSub = null;
    try {
      await _cm.stopDiscovery();
    } catch (_) {}
  }

  Future<String?> connectDevice(RtkDevice d) async {
    await stopScan();
    final p = d.peripheral;
    try {
      status.value = 'Menghubungkan ke ${d.name}...';
      await _cm.connect(p);
      _connected = p;
      connectedName = d.name;
      _buffers.clear();
      final services = await _cm.discoverGATT(p);
      await _nSub?.cancel();
      _nSub = _cm.characteristicNotified.listen(_onData);
      await _cSub?.cancel();
      _cSub = _cm.connectionStateChanged.listen((e) {
        if (e.peripheral.uuid == p.uuid && e.state == ConnectionState.disconnected) {
          _connected = null;
          status.value = 'Terputus';
        }
      });
      var subscribed = 0;
      for (final s in services) {
        if (s.uuid == UUID.short(0x1801)) continue; // Generic Attribute
        for (final c in s.characteristics) {
          if (c.properties.contains(GATTCharacteristicProperty.notify) ||
              c.properties.contains(GATTCharacteristicProperty.indicate)) {
            try {
              await _cm.setCharacteristicNotifyState(p, c, state: true);
              subscribed++;
            } catch (_) {}
          }
        }
      }
      if (subscribed == 0) {
        await disconnect();
        return 'Perangkat tidak punya karakteristik notify (bukan receiver BLE-NMEA?)';
      }
      status.value = 'Terhubung: ${d.name}. Menunggu data NMEA...';
      return null;
    } catch (e) {
      _connected = null;
      status.value = 'Gagal: $e';
      return 'Gagal menghubungkan: $e';
    }
  }

  Future<void> disconnect() async {
    final p = _connected;
    _connected = null;
    await _nSub?.cancel();
    await _cSub?.cancel();
    _nSub = null;
    _cSub = null;
    if (p != null) {
      try {
        await _cm.disconnect(p);
      } catch (_) {}
    }
    latest.value = null;
    latestGst.value = null;
    status.value = 'Belum terhubung';
  }

  void _onData(GATTCharacteristicNotifiedEventArgs e) {
    if (e.peripheral.uuid != _connected?.uuid) return;
    final buf = _buffers.putIfAbsent(e.characteristic.uuid.toString(), NmeaLineBuffer.new);
    for (final line in buf.add(utf8.decode(e.value, allowMalformed: true))) {
      final g = parseGga(line);
      if (g != null) {
        latest.value = g;
        _fixCtrl.add(g);
        continue;
      }
      final s = parseGst(line);
      if (s != null) latestGst.value = s;
    }
  }
}
