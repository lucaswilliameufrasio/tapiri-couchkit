import 'package:flutter/foundation.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/tv_installer.dart';

enum InstallState { loading, idle, connecting, waiting, running, finished }

/// Instala os apps da TV pelo ADB do celular e acompanha cada um.
class InstallTvController extends ChangeNotifier {
  InstallTvController(this._installer);

  final TvInstaller _installer;

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
      final chosen = [
        for (final app in apps)
          if (selected.contains(app.id)) app,
      ];
      failures.addAll(
        await _installer.install(
          host.trim(),
          chosen,
          openFirst: true,
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
      state = InstallState.finished;
    } on AppException catch (e) {
      error = e.message;
      state = InstallState.idle;
    }
    notifyListeners();
  }
}
