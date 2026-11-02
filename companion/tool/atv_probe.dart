// Teste manual contra uma Android TV real (nao envia teclas):
//   dart run tool/atv_probe.dart <ip> <arquivo-do-codigo>
// Inicia o pareamento (a TV mostra um codigo), espera o codigo aparecer no
// arquivo, termina o pareamento e conecta lendo o estado da TV.
// O certificado fica em ~/.cache/couchkit-atv-probe.json (fora do repositorio).
import 'dart:convert';
import 'dart:io';

import 'package:couchkit_remote/data/atv/atv_identity.dart';
import 'package:couchkit_remote/data/atv/atv_pairing.dart';
import 'package:couchkit_remote/data/atv/atv_remote.dart';

Future<void> main(List<String> args) async {
  final host = args[0];
  final codeFile = File(args[1]);
  final cache = File(
    '${Platform.environment['HOME']}/.cache/couchkit-atv-probe.json',
  );
  final AtvIdentity identity;
  if (cache.existsSync()) {
    identity = AtvIdentity.fromJson(
      jsonDecode(cache.readAsStringSync()) as Map<String, dynamic>,
    );
  } else {
    stdout.writeln('gerando certificado...');
    identity = await AtvIdentity.generate();
    cache.writeAsStringSync(jsonEncode(identity.toJson()));
  }

  final remote = AtvRemote(identity);
  try {
    await remote.connect(host);
    stdout.writeln('ja pareado: conectado, TV ligada=${remote.isOn}');
    await remote.close();
    return;
  } on Object catch (e) {
    stdout.writeln('nao conectou ($e): pareando...');
  }

  final pairing = AtvPairing(identity);
  await pairing.start(host);
  stdout.writeln('>> a TV mostra um codigo; escreva-o em ${codeFile.path}');
  for (var i = 0; i < 240; i++) {
    if (codeFile.existsSync() && codeFile.readAsStringSync().trim().isNotEmpty) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await pairing.finish(codeFile.readAsStringSync().trim());
  await pairing.close();
  stdout.writeln('pareado!');
  await remote.close();
  final session = AtvRemote(identity);
  await session.connect(host);
  stdout.writeln('conectado, TV ligada=${session.isOn}');
  await session.close();
}
