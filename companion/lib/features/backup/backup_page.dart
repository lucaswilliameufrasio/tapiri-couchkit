import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/core/ui/widgets.dart';
import 'package:couchkit_remote/data/backup/backup_service.dart';
import 'package:couchkit_remote/features/home/home_controller.dart';
import 'package:couchkit_remote/features/panels/panels_controller.dart';

/// Backup criptografado das configuracoes e restauracao em outro celular.
class BackupPage extends StatefulWidget {
  const BackupPage({required this.service, super.key});

  static const route = '/backup';

  final BackupService service;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  RestoreReport? _report;

  Future<String?> _askPassword({required bool confirm}) {
    return showDialog<String>(
      context: context,
      builder: (context) => _PasswordDialog(confirm: confirm),
    );
  }

  Future<void> _export() async {
    final password = await _askPassword(confirm: true);
    if (password == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final file = await guarded(context, () => widget.service.export(password));
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (file == null) {
      return;
    }
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final saved = await FilePicker.saveFile(
      fileName: 'couchkit-backup-$stamp.ckbk',
      bytes: file,
    );
    if (mounted && saved != null) {
      showMessage(context, 'Backup salvo. Guarde a senha: sem ela não abre.');
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFile();
    final path = picked?.path;
    if (path == null || !mounted) {
      return;
    }
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException {
      if (mounted) {
        showMessage(context, 'Não consegui ler o arquivo.');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final password = await _askPassword(confirm: false);
    if (password == null || !mounted) {
      return;
    }
    final homeController = context.read<HomeController>();
    final panelsController = context.read<PanelsController>();
    setState(() {
      _busy = true;
      _report = null;
    });
    final report = await guarded(
      context,
      () => widget.service.restore(bytes, password),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _report = report;
    });
    if (report != null) {
      await panelsController.load();
      await homeController.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup e restauração')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (_busy) const LinearProgressIndicator(),
          const SectionTitle('Exportar'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Guarda TVs e tokens, nomes, painéis, a chave ADB e as '
                    'configurações do HomeCam e do FireHome (lidas de cada TV '
                    'ligada). O arquivo é criptografado com a sua senha '
                    '(AES-256); quem não tiver a senha não consegue abrir.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Criar backup'),
                    onPressed: _busy ? null : _export,
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Restaurar'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Escolha um arquivo .ckbk e digite a senha. Os dados '
                    'voltam ao celular e as configurações do HomeCam e do '
                    'FireHome são reenviadas às TVs que estiverem ligadas.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restore),
                    label: const Text('Escolher arquivo'),
                    onPressed: _busy ? null : _restore,
                  ),
                ],
              ),
            ),
          ),
          if (report != null) ...[
            const SectionTitle('Resultado'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${report.tvs} TV(s) e ${report.panels} painel(is).'),
                    if (report.adbKey)
                      const Text('Chave ADB restaurada: sem nova aprovação.'),
                    for (final item in report.pushed) Text('✓ $item reenviado'),
                    for (final item in report.failed)
                      Text(
                        '✗ $item: não chegou (TV desligada ou token mudou)',
                        style: TextStyle(color: scheme.error),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.confirm});

  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _password.text;
    if (widget.confirm) {
      if (password.length < 8) {
        setState(() => _error = 'Use pelo menos 8 caracteres.');
        return;
      }
      if (password != _again.text) {
        setState(() => _error = 'As senhas não são iguais.');
        return;
      }
    } else if (password.isEmpty) {
      return;
    }
    Navigator.pop(context, password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirm ? 'Senha do backup' : 'Senha do arquivo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Senha'),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _again,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Repita a senha',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            const Text(
              'Não dá para recuperar: sem a senha o backup não abre.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continuar')),
      ],
    );
  }
}
