import 'dart:async';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'ble_common.dart';
import 'sync_protocol.dart';

/// Sisi Base (BLE peripheral): menyiarkan layanan dan mengirim log tekanan
/// saat Rover meminta.
class BaseSyncServer {
  final BaseSession Function() provider;
  BaseSyncServer({required this.provider});

  final PeripheralManager _pm = PeripheralManager();
  final ValueNotifier<String> status = ValueNotifier('Mati');
  StreamSubscription<GATTCharacteristicWriteRequestedEventArgs>? _wSub;
  GATTCharacteristic? _data;
  bool running = false;
  bool _sending = false;

  Future<String?> start() async {
    if (running) return null;
    final err = await ensureBluetoothReady(peripheral: true);
    if (err != null) return err;
    try {
      final ctrl = GATTCharacteristic.mutable(
        uuid: BleIds.ctrl,
        properties: [GATTCharacteristicProperty.write],
        permissions: [GATTCharacteristicPermission.write],
        descriptors: [],
      );
      final data = GATTCharacteristic.mutable(
        uuid: BleIds.data,
        properties: [GATTCharacteristicProperty.notify],
        permissions: [GATTCharacteristicPermission.read],
        descriptors: [],
      );
      _data = data;
      await _pm.removeAllServices();
      await _pm.addService(GATTService(
        uuid: BleIds.service,
        isPrimary: true,
        includedServices: [],
        characteristics: [ctrl, data],
      ));
      _wSub = _pm.characteristicWriteRequested.listen(_onWrite);
      await _pm.startAdvertising(Advertisement(
        name: 'KonturBase',
        serviceUUIDs: [BleIds.service],
      ));
      running = true;
      status.value = 'Menyiarkan, menunggu Rover...';
      return null;
    } catch (e) {
      status.value = 'Gagal: $e';
      return 'Gagal memulai siaran BLE: $e';
    }
  }

  Future<void> stop() async {
    await _wSub?.cancel();
    _wSub = null;
    try {
      await _pm.stopAdvertising();
      await _pm.removeAllServices();
    } catch (_) {}
    running = false;
    status.value = 'Mati';
  }

  Future<void> _onWrite(GATTCharacteristicWriteRequestedEventArgs e) async {
    if (e.characteristic.uuid != BleIds.ctrl) return;
    await _pm.respondWriteRequest(e.request);
    final v = e.request.value;
    if (v.isNotEmpty && v[0] == 1) {
      await _send(e.central);
    }
  }

  Future<void> _send(Central central) async {
    final data = _data;
    if (_sending || data == null) return;
    _sending = true;
    try {
      final s = provider();
      final payload = encodeSession(s.baseZ, s.log);
      var maxLen = await _pm.getMaximumNotifyLength(central);
      maxLen = maxLen.clamp(20, 180).toInt();
      final packets = packetize(Uint8List.fromList(payload), maxLen);
      for (var i = 0; i < packets.length; i++) {
        status.value = 'Mengirim ${i + 1}/${packets.length}';
        await _pm.notifyCharacteristic(central, data, value: packets[i]);
        if (i % 8 == 7) await Future.delayed(const Duration(milliseconds: 15));
      }
      status.value = 'Terkirim (${s.log.length} entri). Menunggu Rover lain...';
    } catch (e) {
      status.value = 'Gagal kirim: $e';
    } finally {
      _sending = false;
    }
  }
}
