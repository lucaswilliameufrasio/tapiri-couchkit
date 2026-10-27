import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/ui/widgets.dart';
import 'package:couchkit_remote/data/tune_profiles.dart';
import 'package:couchkit_remote/data/tv_adb.dart';
import 'package:couchkit_remote/features/tune/tune_controller.dart';

/// Otimizacao da TV pelo celular, via ADB direto (sem PC).
class TunePage extends StatefulWidget {
  const TunePage({required this.adb, required this.host, super.key});

  static const route = '/tune';

  final TvAdb adb;
  final String host;

  @override
  State<TunePage> createState() => _TunePageState();
}

class _TunePageState extends State<TunePage> {
  late final TuneController _controller = TuneController(
    widget.adb,
    widget.host,
  )..addListener(_changed);

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Otimizar a TV')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _ConnectionCard(controller: controller),
          const SectionTitle('Ajustes'),
          for (final profile in tuneProfiles) ...[
            _ProfileCard(
              profile: profile,
              enabled: !controller.busy,
              running: controller.runningId == profile.id,
              done: controller.lastDone == profile.id,
              progress: controller.runningId == profile.id
                  ? controller.done / controller.total
                  : null,
              onApply: () => controller.run(profile),
              onUndo: () => controller.run(profile, undo: true),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.controller});

  final TuneController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final model = controller.model;
    final (icon, color, title, body) = switch (controller.state) {
      TuneState.waiting => (
        Icons.tv,
        Colors.orange,
        'Aprove na TV',
        'Na TV, aparece "Permitir depuração USB?". Marque "Sempre permitir" '
            'e confirme.',
      ),
      TuneState.connecting => (
        Icons.sync,
        scheme.primary,
        'Conectando…',
        'Falando com o ADB da TV.',
      ),
      TuneState.failed => (
        Icons.error_outline,
        scheme.error,
        'Não conectou',
        '${controller.error}\nSe o ADB do PC estiver conectado, rode '
            '"adb disconnect": a TV aceita um cliente por vez.',
      ),
      _ when model != null => (
        Icons.check_circle,
        Colors.green,
        'Conectado: $model',
        'Os ajustes rodam direto na TV, sem PC.',
      ),
      _ => (
        Icons.usb,
        scheme.primary,
        'Conectar ao ADB da TV',
        'Uma autorização na TV, uma vez só. Depois o celular otimiza '
            'sozinho.',
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (model == null || controller.state == TuneState.failed) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: controller.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(controller.busy ? 'Aguardando…' : 'Conectar'),
                onPressed: controller.busy ? null : controller.connect,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.enabled,
    required this.running,
    required this.done,
    required this.progress,
    required this.onApply,
    required this.onUndo,
  });

  final TuneProfile profile;
  final bool enabled;
  final bool running;
  final bool done;
  final double? progress;
  final VoidCallback onApply;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profile.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              profile.description,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (running)
              LinearProgressIndicator(value: progress, minHeight: 6)
            else
              Row(
                children: [
                  FilledButton(
                    onPressed: enabled ? onApply : null,
                    child: const Text('Aplicar'),
                  ),
                  if (profile.undoable) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: enabled ? onUndo : null,
                      child: const Text('Desfazer'),
                    ),
                  ],
                  if (done) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
