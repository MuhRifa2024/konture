import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as bluetooth;
import 'nmea_parser.dart';

/// Menerima NMEA dari receiver RTK lewat BLE (Nordic UART Service).
/// CATATAN: UUID berbeda tiap merek. Sesuaikan dengan dokumentasi GATT alat Anda.
class BleNmeaSource {
  static final nusService = bluetooth.Guid(
    '6E400001-B5A3-F393-E0A9-E50E24DCCA9E',
  );

  static final nusTx = bluetooth.Guid(
    '6E400003-B5A3-F393-E0A9-E50E24DCCA9E',
  ); // notify

  final _fixCtrl = StreamController<GgaFix>.broadcast();
  final _lines = NmeaLineBuffer();

  bluetooth.BluetoothDevice? _device;
  StreamSubscription<List<int>>? _sub;

  Stream<GgaFix> get fixes => _fixCtrl.stream;

  Stream<List<bluetooth.ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) {
    bluetooth.FlutterBluePlus.startScan(timeout: timeout);
    return bluetooth.FlutterBluePlus.scanResults;
  }

  Future<void> connect(bluetooth.BluetoothDevice device) async {
    _device = device;

    await device.connect(
      license: bluetooth.License.nonprofit,
    );

    final services = await device.discoverServices();

    for (final s in services) {
      if (s.uuid != nusService) continue;

      for (final c in s.characteristics) {
        if (c.uuid == nusTx) {
          await c.setNotifyValue(true);

          _sub = c.onValueReceived.listen((data) {
            for (final line in _lines.add(
              utf8.decode(data, allowMalformed: true),
            )) {
              final fix = parseGga(line);

              if (fix != null) {
                _fixCtrl.add(fix);
              }
            }
          });
        }
      }
    }
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    await _device?.disconnect();
  }
}
