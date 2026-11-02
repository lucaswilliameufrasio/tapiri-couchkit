import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/atv/atv_identity.dart';
import 'package:couchkit_remote/data/atv/atv_messages.dart';
import 'package:couchkit_remote/data/atv/atv_pairing.dart';
import 'package:couchkit_remote/data/atv/protobuf.dart';

/// Sessao de comandos do Android TV Remote v2 (porta 6466). Exige que o
/// celular ja tenha sido pareado ([AtvPairing]).
class AtvRemote {
  AtvRemote(this.identity, {this.apiPort = 6466});

  final AtvIdentity identity;
  final int apiPort;

  // PING | KEY | IME | POWER | VOLUME | APP_LINK
  static const _wanted = 1 | 2 | 4 | 32 | 64 | 512;

  SecureSocket? _socket;
  final _frames = PbFrames();
  final _closed = Completer<void>();
  Completer<void>? _started;
  var _features = _wanted;
  var _imeCounter = 0;
  var _fieldCounter = 0;

  /// Acaba quando a conexao cai.
  Future<void> get onClosed => _closed.future;

  bool get connected => _socket != null && !_closed.isCompleted;

  /// A TV esta ligada (reportado por ela no inicio e a cada mudanca).
  bool isOn = false;

  Future<void> connect(String host) async {
    final SecureSocket socket;
    try {
      socket = await SecureSocket.connect(
        host,
        apiPort,
        context: atvContext(identity),
        onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 5),
      );
    } on HandshakeException {
      throw const AtvException(
        'A TV não reconhece este celular. Faça o pareamento.',
        needsPairing: true,
      );
    } on Object {
      throw const AtvException(
        'Não consegui falar com a TV (desligada ou em outra rede?).',
      );
    }
    _socket = socket;
    _started = Completer<void>();
    socket.listen(
      (data) {
        for (final frame in _frames.add(data)) {
          _handle(PbReader(frame));
        }
      },
      onDone: _finish,
      onError: (Object _) => _finish(),
      cancelOnError: true,
    );
    try {
      await _started!.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      await close();
      throw const AtvException(
        'A TV não reconhece este celular. Faça o pareamento.',
        needsPairing: true,
      );
    }
  }

  void _finish() {
    if (!_closed.isCompleted) {
      _closed.complete();
    }
    final started = _started;
    if (started != null && !started.isCompleted) {
      started.completeError(
        const AtvException(
          'A TV não reconhece este celular. Faça o pareamento.',
          needsPairing: true,
        ),
      );
    }
  }

  void _handle(PbReader msg) {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    if (msg.has(1)) {
      final supported = msg.message(1)!.uint(1);
      _features = _wanted & supported;
      socket.add(RemoteMsg.configure(_features));
    } else if (msg.has(2)) {
      socket.add(RemoteMsg.setActive(_features));
    } else if (msg.has(8)) {
      socket.add(RemoteMsg.pingResponse(msg.message(8)!.uint(1)));
    } else if (msg.has(21)) {
      final edit = msg.message(21)!;
      _imeCounter = edit.uint(1);
      _fieldCounter = edit.uint(2);
    } else if (msg.has(40)) {
      isOn = msg.message(40)!.uint(1) == 1;
      final started = _started;
      if (started != null && !started.isCompleted) {
        started.complete();
      }
    }
  }

  void _send(Uint8List data) {
    if (!connected) {
      throw const AtvException('Conexão com a TV encerrada.');
    }
    _socket!.add(data);
  }

  void sendKey(int code, {int direction = 3}) =>
      _send(RemoteMsg.key(code, direction: direction));

  void sendText(String text) {
    if (text.isEmpty) {
      return;
    }
    _send(RemoteMsg.text(text, _imeCounter, _fieldCounter));
  }

  void launchApp(String link) => _send(RemoteMsg.appLink(link));

  Future<void> close() async {
    _socket?.destroy();
    _socket = null;
    if (!_closed.isCompleted) {
      _closed.complete();
    }
  }
}
