import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/tv_installer.dart';
import 'package:couchkit_remote/data/tv_repository.dart';

enum InstallState { loading, idle, connecting, waiting, running, finished }

/// Instala os apps da TV pelo ADB do celular e acompanha cada um.
class InstallTvController extends ChangeNotifier {
  InstallTvController(this._installer, this._repository);

  final TvInstaller _installer;
  final TvRepository _repository;

  /// Apps da TV que o Couchkit encontrou depois de configurar (0 = nenhum).
  int registered = 0;
  bool get paired => registered > 0;

  static String newToken() {
    const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  InstallState state = InstallState.loading;
  List<TvApp> apps = const [];
  final selected = <String>{};
  final steps = <String, InstallStep>{};
  final sent = <String, double>{};
  final failures = <String, String>{};
  String? error;

  Future<void> load() async {
    apps = await _installer.available();
    selected
      ..clear()
      ..addAll(apps.map((app) => app.id));
    state = InstallState.idle;
    notifyListeners();
  }

  void toggle(String id) {
    if (!selected.remove(id)) {
      selected.add(id);
    }
    notifyListeners();
  }

  bool get busy =>
      state == InstallState.connecting ||
      state == InstallState.waiting ||
      state == InstallState.running;

  Future<void> install(String host) async {
    if (busy || selected.isEmpty) {
      return;
    }
    steps.clear();
    sent.clear();
    failures.clear();
    error = null;
    state = InstallState.connecting;
    notifyListeners();
    try {
      final address = host.trim();
      final token = await _repository.tokenOf(address) ?? newToken();
      final chosen = [
        for (final app in apps)
          if (selected.contains(app.id)) app,
      ];
      failures.addAll(
        await _installer.install(
          address,
          chosen,
          openFirst: true,
          token: token,
          onWaitingApproval: () {
            state = InstallState.waiting;
            notifyListeners();
          },
          onProgress: (app, step, {sent, detail}) {
            state = InstallState.running;
            steps[app.id] = step;
            if (sent != null) {
              this.sent[app.id] = sent;
            }
            notifyListeners();
          },
        ),
      );
      registered = await _repository.adopt(address, token);
      state = InstallState.finished;
    } on AppException catch (e) {
      error = e.message;
      state = InstallState.idle;
    }
    notifyListeners();
  }
}
