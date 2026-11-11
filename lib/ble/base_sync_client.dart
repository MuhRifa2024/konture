import 'dart:async';
import 'dart:io';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'ble_common.dart';
import 'sync_protocol.dart';

class BaseCandidate {
  final Peripheral peripheral;
  final String name;
  final int rssi;
  const BaseCandidate(this.peripheral, this.name, this.rssi);
}

/// Sisi Rover (BLE central): mencari Base dan mengunduh log tekanannya.
/// Dilakukan saat Rover berada dekat Base (BLE hanya beberapa puluh meter).
class BaseSyncClient {
  final CentralManager _cm = CentralManager();
  final ValueNotifier<List<BaseCandidate>> found = ValueNotifier([]);
  final ValueNotifier<String> status = ValueNotifier('Siap');
  StreamSubscription<DiscoveredEventArgs>? _dSub;

  Future<String?> startScan() async {
    final err = await ensureBluetoothReady();
    if (err != null) return err;
    found.value = [];
    await _dSub?.cancel();
    _dSub = _cm.discovered.listen((e) {
      if (!e.advertisement.serviceUUIDs.contains(BleIds.service)) return;
      final cand = BaseCandidate(e.peripheral, e.advertisement.name ?? 'Base', e.rssi);
      final list = [...found.value];
      final i = list.indexWhere((c) => c.peripheral.uuid == e.peripheral.uuid);
      if (i >= 0) {
        list[i] = cand;
      } else {
        list.add(cand);
      }
      found.value = list;
    });
    await _cm.startDiscovery(serviceUUIDs: [BleIds.service]);
    status.value = 'Mencari Base...';
    return null;
  }

  Future<void> stopScan() async {
    await _dSub?.cancel();
    _dSub = null;
    try {
      await _cm.stopDiscovery();
    } catch (_) {}
  }

  Future<BaseSession> fetch(
    Peripheral p, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    await stopScan();
    status.value = 'Menghubungkan...';
    await _cm.connect(p);
    StreamSubscription<GATTCharacteristicNotifiedEventArgs>? nSub;
    try {
      final services = await _cm.discoverGATT(p);
      GATTCharacteristic? ctrl, data;
      for (final s in services) {
        if (s.uuid != BleIds.service) continue;
        for (final c in s.characteristics) {
          if (c.uuid == BleIds.ctrl) ctrl = c;
          if (c.uuid == BleIds.data) data = c;
        }
      }
      if (ctrl == null || data == null) {
        throw StateError('Layanan Kontur tidak ditemukan pada perangkat ini');
      }
      if (Platform.isAndroid) {
        try {
          await _cm.requestMTU(p, mtu: 185);
        } catch (_) {}
      }

      final asm = PacketAssembler();
      final done = Completer<void>();
      nSub = _cm.characteristicNotified.listen((e) {
        if (e.peripheral.uuid != p.uuid || e.characteristic.uuid != BleIds.data) return;
        asm.add(e.value);
        status.value = 'Menerima ${asm.received}/${asm.total ?? '?'} paket';
        if (asm.complete && !done.isCompleted) done.complete();
      });

      await _cm.setCharacteristicNotifyState(p, data, state: true);
      await _cm.writeCharacteristic(
        p,
        ctrl,
        value: Uint8List.fromList([1]),
        type: GATTCharacteristicWriteType.withResponse,
      );
      await done.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
            'Data tidak lengkap (${asm.received}/${asm.total ?? '?'}). Dekatkan HP dan coba lagi.'),
      );

      final bytes = asm.assemble();
      final session = bytes == null ? null : decodeSession(bytes);
      if (session == null) throw StateError('Data dari Base rusak');
      status.value = 'Selesai (${session.log.length} entri)';
      return session;
    } finally {
      await nSub?.cancel();
      try {
        await _cm.disconnect(p);
      } catch (_) {}
    }
  }
}
