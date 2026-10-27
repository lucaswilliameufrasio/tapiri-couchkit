import 'dart:typed_data';

/// Comandos do protocolo ADB (4 letras lidas como inteiro little-endian).
abstract final class AdbCommand {
  static const connect = 0x4e584e43; // CNXN
  static const auth = 0x48545541; // AUTH
  static const open = 0x4e45504f; // OPEN
  static const okay = 0x59414b4f; // OKAY
  static const write = 0x45545257; // WRTE
  static const close = 0x45534c43; // CLSE
}

abstract final class AdbAuth {
  static const token = 1;
  static const signature = 2;
  static const publicKey = 3;
}

class AdbMessage {
  const AdbMessage(this.command, this.arg0, this.arg1, this.data);

  final int command;
  final int arg0;
  final int arg1;
  final Uint8List data;

  static const headerLength = 24;

  Uint8List encode() {
    final out = Uint8List(headerLength + data.length);
    final header = ByteData.sublistView(out);
    var checksum = 0;
    for (final byte in data) {
      checksum += byte;
    }
    header.setUint32(0, command, Endian.little);
    header.setUint32(4, arg0, Endian.little);
    header.setUint32(8, arg1, Endian.little);
    header.setUint32(12, data.length, Endian.little);
    header.setUint32(16, checksum & 0xffffffff, Endian.little);
    header.setUint32(20, command ^ 0xffffffff, Endian.little);
    out.setRange(headerLength, out.length, data);
    return out;
  }
}
