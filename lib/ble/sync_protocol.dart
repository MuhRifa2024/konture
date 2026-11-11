import 'dart:typed_data';

/// Sesi Base: elevasi referensi + log tekanan [tMs, hPa].
class BaseSession {
  final double baseZ;
  final List<List<double>> log;
  const BaseSession(this.baseZ, this.log);
}

const _magic0 = 0x4B, _magic1 = 0x42; // 'KB'
const _headerLen = 14;

/// Biner: 'KB' | baseZ f64 | n u32 | n x (t f64, p f32), little-endian.
Uint8List encodeSession(double baseZ, List<List<double>> log) {
  final b = ByteData(_headerLen + log.length * 12);
  b.setUint8(0, _magic0);
  b.setUint8(1, _magic1);
  b.setFloat64(2, baseZ, Endian.little);
  b.setUint32(10, log.length, Endian.little);
  var o = _headerLen;
  for (final e in log) {
    b.setFloat64(o, e[0], Endian.little);
    b.setFloat32(o + 8, e[1], Endian.little);
    o += 12;
  }
  return b.buffer.asUint8List();
}

BaseSession? decodeSession(Uint8List data) {
  if (data.length < _headerLen) return null;
  final b = ByteData.sublistView(data);
  if (b.getUint8(0) != _magic0 || b.getUint8(1) != _magic1) return null;
  final z = b.getFloat64(2, Endian.little);
  final n = b.getUint32(10, Endian.little);
  if (data.length != _headerLen + n * 12) return null;
  final log = <List<double>>[];
  var o = _headerLen;
  for (var i = 0; i < n; i++) {
    log.add([b.getFloat64(o, Endian.little), b.getFloat32(o + 8, Endian.little)]);
    o += 12;
  }
  return BaseSession(z, log);
}

/// Paket: seq u16 | total u16 | payload. [maxPacket] = ukuran total paket.
List<Uint8List> packetize(Uint8List payload, int maxPacket) {
  if (maxPacket <= 4) throw ArgumentError('maxPacket harus > 4');
  final body = maxPacket - 4;
  final total = (payload.length / body).ceil().clamp(1, 65535).toInt();
  return [
    for (var i = 0; i < total; i++)
      () {
        final start = i * body;
        final end = (start + body) > payload.length ? payload.length : start + body;
        final chunk = payload.sublist(start, end);
        final h = ByteData(4)
          ..setUint16(0, i, Endian.little)
          ..setUint16(2, total, Endian.little);
        return Uint8List.fromList([...h.buffer.asUint8List(), ...chunk]);
      }()
  ];
}

/// Menyusun paket (boleh tidak berurutan) menjadi payload utuh.
class PacketAssembler {
  int? _total;
  final Map<int, Uint8List> _parts = {};

  int get received => _parts.length;
  int? get total => _total;
  bool get complete => _total != null && _parts.length == _total;

  void add(Uint8List packet) {
    if (packet.length < 4) return;
    final b = ByteData.sublistView(packet);
    _total = b.getUint16(2, Endian.little);
    _parts[b.getUint16(0, Endian.little)] = Uint8List.fromList(packet.sublist(4));
  }

  Uint8List? assemble() {
    final t = _total;
    if (t == null || _parts.length != t) return null;
    final out = BytesBuilder();
    for (var i = 0; i < t; i++) {
      final p = _parts[i];
      if (p == null) return null;
      out.add(p);
    }
    return out.takeBytes();
  }
}
