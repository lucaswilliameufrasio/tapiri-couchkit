import 'package:flutter/services.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/adb/adb_connection.dart';
import 'package:couchkit_remote/data/tv_adb.dart';

/// Um app da TV que o Couchkit sabe instalar (APK embutido nos assets).
class TvApp {
  const TvApp(this.id, this.pkg, this.label, this.description);

  final String id;
  final String pkg;
  final String label;
  final String description;

  String get asset => 'assets/tv/$id.apk';
}

const tvApps = [
  TvApp('stickhub', 'com.lucas.stickhub', 'StickHub', 'Base: apps e sistema'),
  TvApp('firehome', 'com.lucas.firehome', 'FireHome', 'Launcher'),
  TvApp('phonebro', 'com.lucas.phonebro', 'PhoneBro', 'Navegador'),
  TvApp('phonecast', 'com.lucas.phonecast', 'PhoneCast', 'Fotos e vídeos'),
  TvApp('stickclock', 'com.lucas.stickclock', 'StickClock', 'Relógio'),
  TvApp('homecam', 'com.lucas.homecam', 'HomeCam', 'Câmeras'),
];

enum InstallStep { sending, installing, done, failed }

typedef InstallProgress = void Function(
  TvApp app,
  InstallStep step, {
  double? sent,
  String? detail,
});

/// Instala os apps da TV por ADB: envia o APK, recria o registro do app
/// (`uninstall -k`, para o tile nao ficar generico no launcher da Amazon)
/// e instala.
class TvInstaller {
  TvInstaller(this._adb, {AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  final TvAdb _adb;
  final AssetBundle _bundle;

  /// Apps cujo APK esta embutido nesta versao do Couchkit.
  Future<List<TvApp>> available() async {
    final found = <TvApp>[];
    for (final app in tvApps) {
      try {
        await _bundle.load(app.asset);
        found.add(app);
      } on Object {
        // APK nao embutido
      }
    }
    return found;
  }

  /// Instala [apps] em ordem. Devolve os que falharam (id -> motivo).
  Future<Map<String, String>> install(
    String host,
    List<TvApp> apps, {
    required InstallProgress onProgress,
    void Function()? onWaitingApproval,
    bool openFirst = false,
  }) async {
    final failures = <String, String>{};
    final connection = await _adb.open(
      host,
      onWaitingApproval: onWaitingApproval,
    );
    try {
      for (final app in apps) {
        try {
          await _installOne(connection, app, onProgress);
          onProgress(app, InstallStep.done);
        } on AppException catch (e) {
          failures[app.id] = e.message;
          onProgress(app, InstallStep.failed, detail: e.message);
        }
      }
      if (openFirst && apps.any((app) => app.id == 'stickhub')) {
        await connection.shell('am start -n com.lucas.stickhub/.MainActivity');
      }
    } finally {
      await connection.close();
    }
    return failures;
  }

  Future<void> _installOne(
    AdbConnection connection,
    TvApp app,
    InstallProgress onProgress,
  ) async {
    final ByteData data;
    try {
      data = await _bundle.load(app.asset);
    } on Object {
      throw AdbException('${app.label}: o APK não veio embutido no Couchkit.');
    }
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final remote = '/data/local/tmp/ck-${app.id}.apk';
    onProgress(app, InstallStep.sending, sent: 0);
    await connection.push(
      Uint8List.fromList(bytes),
      remote,
      onProgress: (sent, total) =>
          onProgress(app, InstallStep.sending, sent: sent / total),
    );
    onProgress(app, InstallStep.installing);
    final listed = await connection.shell('pm list packages ${app.pkg}');
    if (listed.split('\n').contains('package:${app.pkg}')) {
      await connection.shell('pm uninstall -k ${app.pkg}');
    }
    final result = await connection.shell('pm install -r $remote');
    await connection.shell('rm -f $remote');
    if (!result.contains('Success')) {
      throw AdbException('${app.label}: ${result.split('\n').last}');
    }
  }
}
