import 'dart:async';
import 'dart:io';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// UUID layanan sinkronisasi Base -> Rover (16-bit agar muat di paket iklan BLE).
class BleIds {
  static final service = UUID.short(0xA1C0);
  static final ctrl = UUID.short(0xA1C1); // Rover menulis 0x01 = minta log
  static final data = UUID.short(0xA1C2); // Base mengirim log via notify
}

/// Memastikan izin dan status Bluetooth siap. Mengembalikan pesan galat atau null.
Future<String?> ensureBluetoothReady({bool peripheral = false}) async {
  final BluetoothLowEnergyManager m =
      peripheral ? PeripheralManager() : CentralManager();
  if (Platform.isAndroid) {
    final ok = await m.authorize();
    if (!ok) return 'Izin Bluetooth ditolak';
  }
  var st = m.state;
  if (st == BluetoothLowEnergyState.unknown) {
    try {
      st = await m.stateChanged
          .map((e) => e.state)
          .firstWhere((s) => s != BluetoothLowEnergyState.unknown)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      st = m.state;
    }
  }
  return switch (st) {
    BluetoothLowEnergyState.poweredOn => null,
    BluetoothLowEnergyState.poweredOff => 'Nyalakan Bluetooth terlebih dahulu',
    BluetoothLowEnergyState.unauthorized =>
      'Izin Bluetooth ditolak. Aktifkan di pengaturan aplikasi.',
    BluetoothLowEnergyState.unsupported => 'Perangkat tidak mendukung BLE',
    BluetoothLowEnergyState.unknown => 'Bluetooth belum siap, coba lagi',
  };
}
