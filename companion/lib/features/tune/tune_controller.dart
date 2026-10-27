import 'package:flutter/foundation.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/adb/adb_connection.dart';
import 'package:couchkit_remote/data/tune_profiles.dart';
import 'package:couchkit_remote/data/tv_adb.dart';

enum TuneState { idle, connecting, waiting, ready, running, failed }

/// Fala ADB direto do celular com a TV: cada acao abre a sessao, roda e
/// fecha, para nao prender o adbd (que aceita um cliente por vez).
class TuneController extends ChangeNotifier {
  TuneController(this._adb, this.host);

  final TvAdb _adb;
  final String host;

  TuneState state = TuneState.idle;
  String? model;
  String? error;
  String? runningId;
  int done = 0;
  int total = 0;
  String? lastDone;

  bool get busy =>
      state == TuneState.connecting ||
      state == TuneState.waiting ||
      state == TuneState.running;

  /// Confirma que a TV aceita o celular (1a vez: aprovar na TV).
  Future<void> connect() async {
    await _session((connection) async {
      model = (await connection.shell('getprop ro.product.model')).trim();
      state = TuneState.ready;
    });
  }

  Future<void> run(TuneProfile profile, {bool undo = false}) async {
    final commands = undo ? profile.undo : profile.apply;
    await _session((connection) async {
      state = TuneState.running;
      runningId = profile.id;
      done = 0;
      total = commands.length;
      notifyListeners();
      for (final command in commands) {
        await connection.shell(command);
        done++;
        notifyListeners();
      }
      lastDone = profile.id;
      state = TuneState.ready;
    });
    runningId = null;
    notifyListeners();
  }

  Future<void> _session(
    Future<void> Function(AdbConnection connection) body,
  ) async {
    if (busy) {
      return;
    }
    error = null;
    state = TuneState.connecting;
    lastDone = null;
    notifyListeners();
    AdbConnection? connection;
    try {
      connection = await _adb.open(
        host,
        onWaitingApproval: () {
          state = TuneState.waiting;
          notifyListeners();
        },
      );
      await body(connection);
    } on AdbException catch (e) {
      error = e.message;
      state = TuneState.failed;
    } catch (e) {
      error = '$e';
      state = TuneState.failed;
    } finally {
      await connection?.close();
    }
    notifyListeners();
  }
}
