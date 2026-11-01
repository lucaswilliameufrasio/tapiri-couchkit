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

  /// Reenvia [token] ao StickHub pelo ADB (conserto de "token recusado").
  Future<void> setToken(
    String host,
    String token, {
    void Function()? onWaitingApproval,
  }) async {
    final connection = await _adb.open(
      host,
      onWaitingApproval: onWaitingApproval,
    );
    try {
      await _sendToken(connection, token);
      await _enableKeyService(connection);
    } finally {
      await connection.close();
    }
  }

  Future<void> _sendToken(AdbConnection connection, String token) async {
    const hub = 'com.lucas.stickhub';
    final result = await connection.shell(
      'am broadcast --include-stopped-packages '
      '-a $hub.PROVISION -n $hub/.ProvisionReceiver --es token $token',
    );
    if (!result.contains('Broadcast completed')) {
      throw AdbException(
        'O StickHub não aceitou o token: ${result.split('\n').first}',
      );
    }
  }

  static const _keyService = 'com.lucas.stickhub/com.lucas.stickhub.KeyService';

  /// Liga o servico de controle remoto do StickHub (acessibilidade), que
  /// permite usar o controle do Couchkit sem a depuracao ADB.
  Future<void> _enableKeyService(AdbConnection connection) async {
    final current = (await connection.shell(
      'settings get secure enabled_accessibility_services',
    )).trim();
    if (current.split(':').contains(_keyService)) {
      return;
    }
    final value = current.isEmpty || current == 'null'
        ? _keyService
        : '$current:$_keyService';
    await connection.shell(
      "settings put secure enabled_accessibility_services '$value'",
    );
    await connection.shell('settings put secure accessibility_enabled 1');
  }

  /// Liga o controle sem ADB numa TV ja configurada.
  Future<void> enableRemote(String host) async {
    final connection = await _adb.open(host);
    try {
      await _enableKeyService(connection);
    } finally {
      await connection.close();
    }
  }

  /// Desliga a Depuracao ADB da TV. Religar so pelo menu da TV.
  Future<void> disableAdb(String host) async {
    final connection = await _adb.open(host);
    try {
      await connection.shell('settings put global adb_enabled 0');
    } on AdbException {
      // o adbd cai junto com a conexao: esperado
    } finally {
      await connection.close();
    }
  }

  /// Instala [apps] em ordem. Devolve os que falharam (id -> motivo).
  Future<Map<String, String>> install(
    String host,
    List<TvApp> apps, {
    required InstallProgress onProgress,
    void Function()? onWaitingApproval,
    bool openFirst = false,
    String? token,
    Duration launchGap = const Duration(milliseconds: 1500),
    Duration retryGap = const Duration(seconds: 3),
  }) async {
    final failures = <String, String>{};
    final connection = await _adb.open(
      host,
      onWaitingApproval: onWaitingApproval,
    );
    try {
      for (final app in apps) {
        try {
          try {
            await _installOne(connection, app, onProgress);
          } on AdbException {
            // a TV as vezes recusa a primeira (verificacao do sistema)
            await Future<void>.delayed(retryGap);
            await _installOne(connection, app, onProgress);
          }
          onProgress(app, InstallStep.done);
        } on AppException catch (e) {
          failures[app.id] = e.message;
          onProgress(app, InstallStep.failed, detail: e.message);
        }
      }
      if (token != null) {
        await _provision(connection, token, apps, launchGap);
      } else if (openFirst && apps.any((app) => app.id == 'stickhub')) {
        await connection.shell('am start -n com.lucas.stickhub/.MainActivity');
      }
    } finally {
      await connection.close();
    }
    return failures;
  }

  /// Define o token do StickHub (so o shell do ADB pode, permissao DUMP) e
  /// abre cada app uma vez para o servidor dele subir. O StickHub fica por
  /// ultimo, na frente, mostrando o QR.
  Future<void> _provision(
    AdbConnection connection,
    String token,
    List<TvApp> apps,
    Duration gap,
  ) async {
    const hub = 'com.lucas.stickhub';
    await connection.shell('am start -n $hub/.MainActivity');
    await Future<void>.delayed(gap);
    await _sendToken(connection, token);
    await _enableKeyService(connection);
    for (final app in apps) {
      if (app.id == 'stickhub') {
        continue;
      }
      await connection.shell('am start -n ${app.pkg}/.MainActivity');
      await Future<void>.delayed(gap);
    }
    await connection.shell('am start -n $hub/.MainActivity');
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
    try {
      final listed = await connection.shell('pm list packages ${app.pkg}');
      if (listed.split('\n').contains('package:${app.pkg}')) {
        await connection.shell('pm uninstall -k ${app.pkg}');
      }
      // a Fire OS otimiza o app na instalacao: apps grandes passam de 1 min
      final result = await connection.shell(
        'pm install -r $remote',
        timeout: const Duration(minutes: 5),
      );
      if (!result.contains('Success')) {
        throw AdbException('${app.label}: ${result.split('\n').last}');
      }
    } on AdbException {
      rethrow;
    } finally {
      try {
        await connection.shell('rm -f $remote');
      } on Object {
        // conexao ja caiu; o arquivo em /data/local/tmp nao atrapalha
      }
    }
  }
}
