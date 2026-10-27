import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/core/ui/widgets.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';
import 'package:couchkit_remote/features/tune/tune_controller.dart';

/// Otimizacao da TV pelo celular: o StickHub roda os ajustes no ADB local.
class TunePage extends StatefulWidget {
  const TunePage({required this.service, super.key});

  static const route = '/tune';

  final HubService service;

  @override
  State<TunePage> createState() => _TunePageState();
}

class _TunePageState extends State<TunePage> {
  late final TuneController _controller = TuneController(widget.service)
    ..addListener(_changed)
    ..refresh();

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

  Future<void> _run(String id) async {
    final started = await guarded(context, () => _controller.run(id));
    if (!mounted) {
      return;
    }
    if (started == false) {
      showMessage(context, 'Já existe um ajuste em andamento.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _controller.status;
    return Scaffold(
      appBar: AppBar(title: const Text('Otimizar a TV')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _ConnectionCard(
            status: status,
            onConnect: () => guarded(context, _controller.connect),
          ),
          const SectionTitle('Ajustes'),
          for (final profile in tuneProfiles) ...[
            _ProfileCard(
              profile: profile,
              enabled: status.connected && !status.running,
              running:
                  status.tune.contains(':${profile.id}') ||
                  status.tune.contains(':${profile.undoId}'),
              onApply: () => _run(profile.id),
              onUndo: () => _run(profile.undoId),
            ),
            const SizedBox(height: 10),
          ],
          if (status.tune.isNotEmpty) _Progress(text: status.tune),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.status, required this.onConnect});

  final TuneStatus status;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, title, body) = switch (status) {
      TuneStatus(connected: true) => (
        Icons.check_circle,
        Colors.green,
        'Conectado ao ADB da TV',
        'Os ajustes abaixo rodam direto na TV, sem PC.',
      ),
      TuneStatus(waiting: true) => (
        Icons.tv,
        Colors.orange,
        'Aprove na TV',
        'Na TV, aparece "Permitir depuração USB?". Marque "Sempre permitir" '
            'e confirme.',
      ),
      TuneStatus(error: final message?) => (
        Icons.error_outline,
        scheme.error,
        'Não conectou',
        '$message. Confira se a Depuração ADB está ligada em Configurações → '
            'Meu Fire TV → Opções do desenvolvedor.',
      ),
      _ => (
        Icons.usb,
        scheme.primary,
        'Conectar ao ADB da TV',
        'Uma autorização na TV, uma vez só. Depois o celular otimiza sozinho.',
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
            if (!status.connected) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: status.waiting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(status.waiting ? 'Aguardando…' : 'Conectar'),
                onPressed: status.waiting ? null : onConnect,
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
    required this.onApply,
    required this.onUndo,
  });

  final TuneProfile profile;
  final bool enabled;
  final bool running;
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
            Row(
              children: [
                FilledButton(
                  onPressed: enabled ? onApply : null,
                  child: const Text('Aplicar'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: enabled ? onUndo : null,
                  child: const Text('Desfazer'),
                ),
                if (running) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final parts = text.split(':');
    final label = switch (parts.first) {
      'rodando' => 'Rodando ${parts.length > 2 ? parts[2] : ''}…',
      'ok' => 'Concluído',
      _ => 'Falhou: ${parts.skip(2).join(':')}',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
