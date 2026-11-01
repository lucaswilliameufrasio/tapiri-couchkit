import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/tv_adb.dart';

/// Um app que atende ao botao Home da TV.
class HomeApp {
  const HomeApp(this.component, {this.current = false});

  final String component;
  final bool current;

  String get pkg => component.split('/').first;
}

class LauncherState {
  const LauncherState(this.apps, {required this.supported});

  final List<HomeApp> apps;
  final bool supported;
}

/// Troca o launcher padrao pelo ADB (`cmd package set-home-activity`,
/// Android 9+). O Fire OS 5 protege o launcher da Amazon: nao muda la.
class TvLauncher {
  TvLauncher(this._adb);

  final TvAdb _adb;

  static const _query =
      '-a android.intent.action.MAIN -c android.intent.category.HOME';

  /// Componentes `pacote/Atividade` de um `cmd package query-activities`.
  static List<String> parseComponents(String output) {
    final found = <String>[];
    final pattern = RegExp(r'^\s*([A-Za-z0-9_.]+/\S+)\s*$');
    for (final line in output.split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match != null && !found.contains(match.group(1))) {
        found.add(match.group(1)!);
      }
    }
    return found;
  }

  Future<LauncherState> load(
    String host, {
    void Function()? onWaitingApproval,
  }) async {
    final connection = await _adb.open(
      host,
      onWaitingApproval: onWaitingApproval,
    );
    try {
      final sdk = int.tryParse(
        (await connection.shell('getprop ro.build.version.sdk')).trim(),
      );
      if (sdk == null || sdk < 28) {
        return const LauncherState([], supported: false);
      }
      final listed = parseComponents(
        await connection.shell('cmd package query-activities --brief $_query'),
      );
      final current = await _current(connection);
      return LauncherState([
        for (final component in listed)
          if (!component.contains('FallbackHome'))
            HomeApp(component, current: component == current),
      ], supported: true);
    } finally {
      await connection.close();
    }
  }

  Future<String?> _current(dynamic connection) async {
    final out = await connection.shell(
      'cmd package resolve-activity --brief $_query',
    );
    final parsed = parseComponents(out as String);
    return parsed.isEmpty ? null : parsed.last;
  }

  /// Define [component] como Home. Devolve false se a TV nao aderiu (alguns
  /// launchers de fabricante ignoram a troca).
  Future<bool> set(String host, String component) async {
    final connection = await _adb.open(host);
    try {
      await connection.shell(
        'cmd package set-home-activity --user 0 $component',
      );
      if (await _current(connection) == component) {
        return true;
      }
      final pkg = component.split('/').first;
      await connection.shell(
        'cmd role add-role-holder --user 0 android.app.role.HOME $pkg',
      );
      return await _current(connection) == component;
    } on AdbException {
      rethrow;
    } finally {
      await connection.close();
    }
  }
}
