import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kontur_survey/ble/sync_protocol.dart';

void main() {
  final log = [
    for (var i = 0; i < 500; i++) [1700000000000.0 + i * 5000, 1000.0 + i * 0.01]
  ];

  test('encode/decode sesi Base bolak-balik', () {
    final s = decodeSession(encodeSession(1234.5, log))!;
    expect(s.baseZ, 1234.5);
    expect(s.log.length, 500);
    expect(s.log[10][0], 1700000000000.0 + 50000);
    expect(s.log[10][1], closeTo(1000.1, 1e-3));
  });

  test('data rusak ditolak', () {
    final bytes = encodeSession(1, log);
    expect(decodeSession(Uint8List.sublistView(bytes, 0, bytes.length - 3)), isNull);
    expect(decodeSession(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('paket dapat disusun walau urutan terbalik', () {
    final payload = encodeSession(10, log);
    final packets = packetize(payload, 100);
    expect(packets.length, greaterThan(10));
    final asm = PacketAssembler();
    for (final p in packets.reversed) {
      asm.add(p);
    }
    expect(asm.complete, isTrue);
    expect(asm.assemble(), payload);
  });

  test('paket hilang -> tidak lengkap', () {
    final packets = packetize(encodeSession(10, log), 100);
    final asm = PacketAssembler();
    for (var i = 0; i < packets.length; i++) {
      if (i != 3) asm.add(packets[i]);
    }
    expect(asm.complete, isFalse);
    expect(asm.assemble(), isNull);
  });
}
