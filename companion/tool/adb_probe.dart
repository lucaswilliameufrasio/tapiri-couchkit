// Teste manual contra um adbd real: dart run tool/adb_probe.dart <ip> [comando]
// A chave fica em ~/.cache/couchkit-adb-probe.json (fora do repositório).
import 'dart:convert';
import 'dart:io';

import 'package:couchkit_remote/data/adb/adb_connection.dart';
import 'package:couchkit_remote/data/adb/adb_key.dart';

Future<void> main(List<String> args) async {
  final host = args.first;
  final file = File(
    '${Platform.environment['HOME']}/.cache/couchkit-adb-probe.json',
  );
  final AdbKey key;
  if (file.existsSync()) {
    key = AdbKey.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
  } else {
    stdout.writeln('gerando chave...');
    key = await AdbKey.generate();
    file.writeAsStringSync(jsonEncode(key.toJson()));
  }
  final connection = await AdbConnection.open(
    host,
    key,
    onWaitingApproval: () =>
        stdout.writeln('>> aprove na TV (Sempre permitir)'),
  );
  stdout.writeln('conectado');
  final command = args.length > 1 ? args[1] : 'getprop ro.product.model';
  stdout.writeln(await connection.shell(command));
  await connection.close();
}
