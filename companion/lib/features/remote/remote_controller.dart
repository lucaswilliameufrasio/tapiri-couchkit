import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/adb/adb_connection.dart';
import 'package:couchkit_remote/data/atv/atv_pairing.dart';
import 'package:couchkit_remote/data/atv/atv_remote.dart';
import 'package:couchkit_remote/data/atv/atv_service.dart';
import 'package:couchkit_remote/data/tv_adb.dart';

enum RemoteState { connecting, waiting, needsPairing, enterCode, ready, failed }

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

/// Controle remoto. Na Android TV / Google TV usa o protocolo Remote v2 (so
/// rede, autenticado por certificado: pareia uma vez com o codigo da tela e
/// dispensa a depuracao ADB). Sem ele (Fire TV), usa uma sessao ADB aberta
/// enquanto a tela esta em uso. As teclas saem em fila, na ordem tocada.
class RemoteController extends ChangeNotifier {
  RemoteController(this._adb, this.host, {AtvService? atv}) : _atvService = atv;

  final TvAdb _adb;
  final String host;
  final AtvService? _atvService;

  RemoteState state = RemoteState.connecting;
  String? error;

  /// Usando o Remote v2 (sem ADB).
  bool viaAtv = false;

  AdbConnection? _connection;
  AtvRemote? _atv;
  AtvPairing? _pairing;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  Future<void> connect() async {
    state = RemoteState.connecting;
    error = null;
    viaAtv = false;
    _notify();
    final service = _atvService;
    if (service != null) {
      try {
        await _connectAtv(service);
        return;
      } on AtvException catch (e) {
        if (e.needsPairing) {
          state = RemoteState.needsPairing;
          _notify();
          return;
        }
        // sem Remote v2 (ex.: Fire TV): segue para o ADB
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

  Future<void> _connectAtv(AtvService service) async {
    await _atv?.close();
    final remote = await service.remote();
    await remote.connect(host);
    _atv = remote;
    viaAtv = true;
    state = RemoteState.ready;
    _notify();
  }

  /// Comeca o pareamento: a TV passa a mostrar um codigo de 6 caracteres.
  Future<void> startPairing() async {
    final service = _atvService;
    if (service == null) {
      return;
    }
    error = null;
    state = RemoteState.connecting;
    _notify();
    try {
      await _pairing?.close();
      final pairing = await service.pairing();
      await pairing.start(host);
      _pairing = pairing;
      state = RemoteState.enterCode;
    } on AtvException catch (e) {
      error = e.message;
      state = RemoteState.needsPairing;
    }
    _notify();
  }

  /// Confere o codigo da TV; se certo, conecta.
  Future<void> submitCode(String code) async {
    final pairing = _pairing;
    if (pairing == null) {
      return;
    }
    error = null;
    try {
      await pairing.finish(code);
    } on AtvException catch (e) {
      error = e.message;
      _notify();
      return;
    }
    await pairing.close();
    _pairing = null;
    await connect();
  }

  void press(RemoteKey key) {
    if (viaAtv) {
      final code = _atvCode(key);
      if (code != null) {
        _atvDo((remote) => remote.sendKey(code));
      }
      return;
    }
    _send('input keyevent ${key.code}');
  }

  int? _atvCode(RemoteKey key) {
    final on = _atv?.isOn ?? true;
    return switch (key) {
      RemoteKey.sleep => on ? 26 : null,
      RemoteKey.wakeup => on ? null : 26,
      _ => key.code,
    };
  }

  /// Abre as configuracoes da TV (a engrenagem do app da Amazon).
  void openSettings() {
    if (viaAtv) {
      _atvDo((remote) => remote.sendKey(176));
      return;
    }
    _send('am start -a android.settings.SETTINGS');
  }

  /// Apaga um caractere do campo em foco.
  void backspace() {
    if (viaAtv) {
      _atvDo((remote) => remote.sendKey(67));
      return;
    }
    _send('input keyevent 67');
  }

  /// Digita [text] no campo em foco da TV.
  void type(String text) {
    if (viaAtv) {
      if (text.isNotEmpty) {
        _atvDo((remote) => remote.sendText(text));
      }
      return;
    }
    final safe = text.replaceAll(RegExp(r'[^A-Za-z0-9 ._@-]'), '');
    if (safe.isEmpty) {
      return;
    }
    _send("input text '${safe.replaceAll(' ', '%s')}'");
  }

  void _atvDo(void Function(AtvRemote remote) action) {
    if (_disposed) {
      return;
    }
    _queue = _queue.then((_) async {
      try {
        var remote = _atv;
        if (remote == null || !remote.connected) {
          // a TV fecha a conexao parada: reconecta sem perder a tecla
          final service = _atvService;
          if (service == null) {
            return;
          }
          await _connectAtv(service);
          remote = _atv;
        }
        action(remote!);
      } on AtvException catch (e) {
        error = e.message;
        state = e.needsPairing ? RemoteState.needsPairing : RemoteState.failed;
        _notify();
      }
    });
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
    _queue = _queue.whenComplete(() async {
      await _connection?.close();
      await _atv?.close();
      await _pairing?.close();
    });
    super.dispose();
  }
}
