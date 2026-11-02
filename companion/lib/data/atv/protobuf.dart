import 'dart:convert';
import 'dart:typed_data';

/// Escritor protobuf minimo (so o que o protocolo do Android TV Remote usa).
class PbWriter {
  final _out = BytesBuilder();

  void _varint(int value) {
    var v = value;
    while (v >= 0x80) {
      _out.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _out.addByte(v);
  }

  void _tag(int field, int wire) => _varint((field << 3) | wire);

  void uint(int field, int value) {
    _tag(field, 0);
    _varint(value);
  }

  void boolean(int field, {required bool value}) => uint(field, value ? 1 : 0);

  void bytes(int field, List<int> value) {
    _tag(field, 2);
    _varint(value.length);
    _out.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void message(int field, PbWriter inner) => bytes(field, inner.toBytes());

  Uint8List toBytes() => _out.toBytes();

  /// Mensagem com o tamanho na frente (varint), como vai pelo socket.
  Uint8List toFrame() {
    final body = toBytes();
    final head = PbWriter().._varint(body.length);
    return Uint8List.fromList([...head.toBytes(), ...body]);
  }
}

/// Leitor: separa os campos de uma mensagem (varint -> int, o resto -> bytes).
class PbReader {
  PbReader(Uint8List data) {
    var pos = 0;
    int varint() {
      var result = 0;
      var shift = 0;
      while (true) {
        final byte = data[pos++];
        result |= (byte & 0x7f) << shift;
        if (byte & 0x80 == 0) {
          return result;
        }
        shift += 7;
      }
    }

    while (pos < data.length) {
      final key = varint();
      final field = key >> 3;
      final dynamic value;
      switch (key & 7) {
        case 0:
          value = varint();
        case 2:
          final length = varint();
          value = Uint8List.sublistView(data, pos, pos + length);
          pos += length;
        case 1:
          value = Uint8List.sublistView(data, pos, pos + 8);
          pos += 8;
        case 5:
          value = Uint8List.sublistView(data, pos, pos + 4);
          pos += 4;
        default:
          throw const FormatException('protobuf: tipo de campo desconhecido');
      }
      (_fields[field] ??= []).add(value);
    }
  }

  final _fields = <int, List<dynamic>>{};

  bool has(int field) => _fields.containsKey(field);

  int uint(int field, [int fallback = 0]) {
    final value = _fields[field]?.first;
    return value is int ? value : fallback;
  }

  Uint8List? bytes(int field) {
    final value = _fields[field]?.first;
    return value is Uint8List ? value : null;
  }

  String string(int field) {
    final raw = bytes(field);
    return raw == null ? '' : utf8.decode(raw, allowMalformed: true);
  }

  PbReader? message(int field) {
    final raw = bytes(field);
    return raw == null ? null : PbReader(raw);
  }
}

/// Junta os bytes de um socket e entrega cada mensagem completa
/// (varint do tamanho + corpo), mesmo que cheguem picadas ou coladas.
class PbFrames {
  var _buffer = Uint8List(0);

  List<Uint8List> add(List<int> chunk) {
    _buffer = Uint8List.fromList([..._buffer, ...chunk]);
    final out = <Uint8List>[];
    while (true) {
      var pos = 0;
      var length = 0;
      var shift = 0;
      var complete = false;
      while (pos < _buffer.length) {
        final byte = _buffer[pos++];
        length |= (byte & 0x7f) << shift;
        shift += 7;
        if (byte & 0x80 == 0) {
          complete = true;
          break;
        }
      }
      if (!complete || _buffer.length < pos + length) {
        return out;
      }
      out.add(Uint8List.sublistView(_buffer, pos, pos + length));
      _buffer = Uint8List.sublistView(_buffer, pos + length);
    }
  }
}
