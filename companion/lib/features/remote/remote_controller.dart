import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/adb/adb_connection.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';
import 'package:couchkit_remote/data/tv_adb.dart';

enum RemoteState { connecting, waiting, ready, failed }

/// Teclas do controle (KeyEvent do Android).
enum RemoteKey {
  up(19),
  down(20),
  left(21),
  right(22),
  ok(23),
  back(4),
  home(3),
  menu(82),
  playPause(85),
  rewind(89),
  forward(90),
  volumeUp(24),
  volumeDown(25),
  mute(164),
  sleep(223),
  wakeup(224);

  const RemoteKey(this.code);

  final int code;
}

/// Controle remoto. Prefere o servico de controle do StickHub (HTTP, nao
/// precisa de ADB ligado); sem ele, usa uma sessao ADB aberta enquanto a tela
/// esta em uso. As teclas saem em fila, na ordem em que foram tocadas.
class RemoteController extends ChangeNotifier {
  RemoteController(this._adb, this.host, {this.hub});

  final TvAdb _adb;
  final String host;
  final HubService? hub;

  /// Controle sem ADB em uso.
  bool viaHub = false;

  /// Aviso passageiro para a tela mostrar (tecla nao executada, etc.).
  String? notice;

  RemoteState state = RemoteState.connecting;
  String? error;
  AdbConnection? _connection;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  Future<void> connect() async {
    state = RemoteState.connecting;
    error = null;
    _notify();
    viaHub = false;
    final hub = this.hub;
    if (hub != null) {
      try {
        viaHub = (await hub.info()).remote;
      } on AppException {
        viaHub = false;
      }
      if (viaHub) {
        state = RemoteState.ready;
        _notify();
        return;
      }
    }
    try {
      await _connection?.close();
      _connection = await _adb.open(
        host,
        onWaitingApproval: () {
          state = RemoteState.waiting;
          _notify();
        },
      );
      state = RemoteState.ready;
    } on AdbException catch (e) {
      error = e.message;
      state = RemoteState.failed;
    }
    _notify();
  }

  void press(RemoteKey key) {
    final hub = this.hub;
    if (viaHub && hub != null && key != RemoteKey.menu) {
      if (key == RemoteKey.wakeup) {
        _hubCall(
          () => throw const AdbException('Acordar a TV precisa do ADB.'),
        );
        return;
      }
      _hubCall(() => hub.key(key.code));
      return;
    }
    if (viaHub) {
      _hubCall(
        () => throw const AdbException('O botão Menu precisa do ADB ligado.'),
      );
      return;
    }
    _send('input keyevent ${key.code}');
  }

  /// Abre as configuracoes da Fire TV (a engrenagem do app da Amazon).
  void openSettings() {
    final hub = this.hub;
    if (viaHub && hub != null) {
      _hubCall(hub.openSettings);
      return;
    }
    _send('am start -a android.settings.SETTINGS');
  }

  void backspace() {
    final hub = this.hub;
    if (viaHub && hub != null) {
      _hubCall(hub.backspace);
      return;
    }
    _send('input keyevent 67');
  }

  void _hubCall(Future<void> Function() call) {
    if (_disposed) {
      return;
    }
    _queue = _queue.then((_) async {
      try {
        await call();
      } on AppException catch (e) {
        notice = e.message;
        _notify();
      }
    });
  }

  /// Digita [text] no campo em foco da TV.
  void type(String text) {
    final hub = this.hub;
    if (viaHub && hub != null) {
      if (text.isNotEmpty) {
        _hubCall(() => hub.typeText(text));
      }
      return;
    }
    final safe = text.replaceAll(RegExp(r'[^A-Za-z0-9 ._@-]'), '');
    if (safe.isEmpty) {
      return;
    }
    _send("input text '${safe.replaceAll(' ', '%s')}'");
  }

  void _send(String command) {
    if (_disposed) {
      return;
    }
    _queue = _queue.then((_) async {
      final connection = _connection;
      if (connection == null || state != RemoteState.ready) {
        return;
      }
      try {
        await connection.shell(command);
      } on AdbException catch (e) {
        error = e.message;
        state = RemoteState.failed;
        _notify();
      }
    });
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // as teclas ja tocadas terminam de sair antes de fechar a sessao
    _queue = _queue.whenComplete(() => _connection?.close());
    super.dispose();
  }
}
