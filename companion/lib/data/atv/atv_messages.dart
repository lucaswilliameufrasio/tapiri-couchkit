import 'dart:typed_data';

import 'package:couchkit_remote/data/atv/protobuf.dart';

/// Mensagens do pareamento (polo.proto, OuterMessage).
abstract final class Polo {
  static const statusOk = 200;

  static PbWriter _outer(void Function(PbWriter w) fill) {
    final w = PbWriter()
      ..uint(1, 2)
      ..uint(2, statusOk);
    fill(w);
    return w;
  }

  static Uint8List pairingRequest(String clientName) => _outer((w) {
    w.message(
      10,
      PbWriter()
        ..string(1, 'atvremote')
        ..string(2, clientName),
    );
  }).toFrame();

  static Uint8List options() => _outer((w) {
    w.message(
      20,
      PbWriter()
        ..message(
          1,
          PbWriter()
            ..uint(1, 3)
            ..uint(2, 6),
        )
        ..uint(3, 1),
    );
  }).toFrame();

  static Uint8List configuration() => _outer((w) {
    w.message(
      30,
      PbWriter()
        ..message(
          1,
          PbWriter()
            ..uint(1, 3)
            ..uint(2, 6),
        )
        ..uint(2, 1),
    );
  }).toFrame();

  static Uint8List secret(List<int> hash) => _outer((w) {
    w.message(40, PbWriter()..bytes(1, hash));
  }).toFrame();

  /// Resposta da TV (para os testes): so o status e o campo de fase.
  static Uint8List reply(int field, {int status = statusOk, PbWriter? body}) {
    final w = PbWriter()
      ..uint(1, 2)
      ..uint(2, status);
    if (field != 0) {
      w.message(field, body ?? PbWriter());
    }
    return w.toFrame();
  }
}

/// Mensagens de comando (remotemessage.proto, RemoteMessage).
abstract final class RemoteMsg {
  static Uint8List configure(int features) {
    final info = PbWriter()
      ..uint(3, 1)
      ..string(4, '1')
      ..string(5, 'atvremote')
      ..string(6, '1.0.0');
    return (PbWriter()..message(
          1,
          PbWriter()
            ..uint(1, features)
            ..message(2, info),
        ))
        .toFrame();
  }

  static Uint8List setActive(int active) {
    return (PbWriter()..message(2, PbWriter()..uint(1, active))).toFrame();
  }

  static Uint8List pingResponse(int value) {
    return (PbWriter()..message(9, PbWriter()..uint(1, value))).toFrame();
  }

  /// direction: 1 = START_LONG, 2 = END_LONG, 3 = SHORT.
  static Uint8List key(int code, {int direction = 3}) {
    return (PbWriter()..message(
          10,
          PbWriter()
            ..uint(1, code)
            ..uint(2, direction),
        ))
        .toFrame();
  }

  static Uint8List text(String text, int imeCounter, int fieldCounter) {
    final last = text.length - 1;
    final edit = PbWriter()
      ..uint(1, 1)
      ..message(
        2,
        PbWriter()
          ..uint(1, last)
          ..uint(2, last)
          ..string(3, text),
      );
    return (PbWriter()..message(
          21,
          PbWriter()
            ..uint(1, imeCounter)
            ..uint(2, fieldCounter)
            ..message(3, edit),
        ))
        .toFrame();
  }

  static Uint8List appLink(String link) {
    return (PbWriter()..message(90, PbWriter()..string(1, link))).toFrame();
  }
}
