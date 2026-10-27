import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';

/// Escolhe um .apk no celular e manda para a TV instalar.
/// Devolve false se o usuario cancelou ou escolheu um arquivo invalido.
Future<bool> installApkFlow(
  BuildContext context,
  HubService service, {
  required void Function(double? progress) onProgress,
}) async {
  final picked = await FilePicker.pickFile();
  final path = picked?.path;
  if (path == null || !context.mounted) {
    return false;
  }
  if (!path.toLowerCase().endsWith('.apk')) {
    showMessage(context, 'Escolha um arquivo .apk');
    return false;
  }
  onProgress(0);
  final message = await guarded(
    context,
    () => service.installApk(
      File(path),
      onProgress: (sent, total) {
        if (total > 0) {
          onProgress(sent / total);
        }
      },
    ),
  );
  onProgress(null);
  if (context.mounted && message != null) {
    showMessage(
      context,
      message.isEmpty ? 'Enviado. Confirme a instalação na TV.' : message,
    );
  }
  return message != null;
}
