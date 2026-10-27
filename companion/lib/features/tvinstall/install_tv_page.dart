import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/ui/widgets.dart';
import 'package:couchkit_remote/data/tv_installer.dart';
import 'package:couchkit_remote/features/tvinstall/install_tv_controller.dart';

/// Instala os apps da TV direto do celular (ADB), sem PC nem Downloader.
class InstallTvPage extends StatefulWidget {
  const InstallTvPage({required this.installer, this.host, super.key});

  static const route = '/install-tv';

  final TvInstaller installer;
  final String? host;

  @override
  State<InstallTvPage> createState() => _InstallTvPageState();
}

class _InstallTvPageState extends State<InstallTvPage> {
  late final InstallTvController _controller = InstallTvController(
    widget.installer,
  )..addListener(_changed);
  late final TextEditingController _host = TextEditingController(
    text: widget.host ?? '',
  );

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

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
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Instalar apps da TV')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            'Na TV: Configurações → Meu Fire TV → Opções do desenvolvedor → '
            'Depuração ADB (ligada). O celular precisa estar na mesma rede.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _host,
            enabled: !controller.busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Endereço da TV (IP)',
              hintText: 'ex.: 192.168.0.20',
            ),
          ),
          const SectionTitle('Apps'),
          if (controller.state == InstallState.loading)
            const Center(child: CircularProgressIndicator())
          else if (controller.apps.isEmpty)
            const EmptyPane(
              icon: Icons.inventory_2_outlined,
              title: 'Sem APKs embutidos',
              message:
                  'Esta versão do Couchkit não trouxe os APKs da TV. Gere com '
                  '"python3 tools/dist.py --build --tv".',
            )
          else
            for (final app in controller.apps)
              _AppTile(
                app: app,
                checked: controller.selected.contains(app.id),
                enabled: !controller.busy,
                step: controller.steps[app.id],
                sent: controller.sent[app.id],
                failure: controller.failures[app.id],
                onChanged: () => controller.toggle(app.id),
              ),
          const SizedBox(height: 12),
          _StatusCard(controller: controller),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.download),
            label: Text(controller.busy ? 'Instalando…' : 'Instalar'),
            onPressed: controller.busy || controller.selected.isEmpty
                ? null
                : () => controller.install(_host.text),
          ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.checked,
    required this.enabled,
    required this.step,
    required this.sent,
    required this.failure,
    required this.onChanged,
  });

  final TvApp app;
  final bool checked;
  final bool enabled;
  final InstallStep? step;
  final double? sent;
  final String? failure;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final trailing = switch (step) {
      InstallStep.sending => SizedBox(
        width: 40,
        child: LinearProgressIndicator(value: sent),
      ),
      InstallStep.installing => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      InstallStep.done => const Icon(Icons.check_circle, color: Colors.green),
      InstallStep.failed => Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      null => null,
    };
    return CheckboxListTile(
      value: checked,
      onChanged: enabled ? (_) => onChanged() : null,
      title: Text(app.label),
      subtitle: Text(failure ?? app.description),
      secondary: trailing,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final InstallTvController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (controller.state) {
      InstallState.waiting => (
        Icons.tv,
        Colors.orange,
        'Aprove na TV: "Permitir depuração USB?" → "Sempre permitir".',
      ),
      InstallState.connecting => (
        Icons.sync,
        scheme.primary,
        'Conectando ao ADB da TV…',
      ),
      InstallState.finished when controller.failures.isEmpty => (
        Icons.check_circle,
        Colors.green,
        'Pronto. O StickHub abriu na TV: aperte MENU no controle para '
            'mostrar o QR e escaneie na tela inicial do Couchkit.',
      ),
      InstallState.finished => (
        Icons.warning_amber,
        scheme.error,
        'Terminou com falhas; veja os apps marcados.',
      ),
      _ when controller.error != null => (
        Icons.error_outline,
        scheme.error,
        '${controller.error}\nSe o ADB do PC estiver conectado, rode '
            '"adb disconnect": a TV aceita um cliente por vez.',
      ),
      _ => (Icons.info_outline, scheme.onSurfaceVariant, ''),
    };
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
