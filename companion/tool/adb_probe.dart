// Teste manual contra um adbd real:
//   dart run tool/adb_probe.dart <ip> [comando]
//   dart run tool/adb_probe.dart <ip> push <arquivo> <destino>
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
  if (args.length > 3 && args[1] == 'push') {
    // push <arquivo local> <destino na TV>
    await connection.push(
      File(args[2]).readAsBytesSync(),
      args[3],
      onProgress: (sent, total) => stdout.writeln('enviado $sent/$total'),
    );
    stdout.writeln(await connection.shell('ls -l ${args[3]}'));
    await connection.close();
    return;
  }
  final command = args.length > 1 ? args[1] : 'getprop ro.product.model';
  stdout.writeln(await connection.shell(command));
  await connection.close();
}
