import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:couchkit_remote/core/di/injector.dart';
import 'package:couchkit_remote/core/navigation/router.dart';
import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/core/ui/widgets.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';
import 'package:couchkit_remote/features/home/home_controller.dart';
import 'package:couchkit_remote/features/hub/install_flow.dart';

/// Resumo da TV, atalhos rapidos e os apps do couchkit.
class HomeTab extends StatefulWidget {
  const HomeTab({required this.hub, required this.endpoint, super.key});

  final HubService? hub;
  final TvEndpoint? endpoint;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  DeviceInfo? _info;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  @override
  void didUpdateWidget(HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endpoint != widget.endpoint) {
      _info = null;
      _loadInfo();
    }
  }

  Future<void> _loadInfo() async {
    final hub = widget.hub;
    if (hub == null) {
      return;
    }
    final info = await guarded(context, hub.info);
    if (mounted && info != null) {
      setState(() => _info = info);
    }
  }

  Future<void> _refresh() async {
    await context.read<HomeController>().refresh();
    await _loadInfo();
  }

  Future<void> _clean() async {
    await guarded(context, widget.hub!.clean);
    if (!mounted) {
      return;
    }
    await _loadInfo();
    if (mounted) {
      showMessage(context, 'Memória liberada');
    }
  }

  Future<void> _install() async {
    await installApkFlow(
      context,
      widget.hub!,
      onProgress: (value) {
        if (mounted) {
          setState(() => _progress = value);
        }
      },
    );
  }

  Future<void> _openLink() async {
    final link = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _LinkSheet(),
    );
    if (link == null || link.isEmpty || !mounted) {
      return;
    }
    final message = await guarded(context, () async {
      await widget.hub!.openUrl(link);
      return 'Enviado ao navegador da TV';
    });
    if (mounted && message != null) {
      showMessage(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    final router = context.read<Injector>().get<RouterService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Couchkit'),
        actions: [
          IconButton(
            tooltip: 'Adicionar app da TV',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => router.push<void>(context, '/add'),
          ),
        ],
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : controller.endpoints.isEmpty
          ? _Onboarding(
              onScan: () => router.push<void>(context, '/add'),
              onInstall: () => router.push<void>(context, '/install-tv'),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (_progress != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(value: _progress),
                    ),
                  _TvCard(
                    controller: controller,
                    info: _info,
                    hasHub: widget.hub != null,
                    onPair: () => router.push<void>(context, '/add'),
                  ),
                  const SectionTitle('Atalhos'),
                  _Shortcuts(
                    enabled: widget.hub != null && _progress == null,
                    onClean: _clean,
                    onLink: _openLink,
                    onInstall: _install,
                  ),
                  const SizedBox(height: 10),
                  _TuneCard(
                    enabled: widget.endpoint != null,
                    onTap: () => router.push<void>(
                      context,
                      '/tune',
                      args: widget.endpoint,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InstallCard(
                    onTap: () => router.push<void>(
                      context,
                      '/install-tv',
                      args: controller.currentHost,
                    ),
                  ),
                  const SectionTitle('Apps do couchkit'),
                  _AppGrid(controller: controller, router: router),
                ],
              ),
            ),
    );
  }
}

class _TvCard extends StatelessWidget {
  const _TvCard({
    required this.controller,
    required this.info,
    required this.hasHub,
    required this.onPair,
  });

  final HomeController controller;
  final DeviceInfo? info;
  final bool hasHub;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final host = controller.currentHost ?? '';
    final online = controller.onlineCount;
    final total = controller.current.length;
    final info = this.info;
    String gb(int mb) => '${(mb / 1024).toStringAsFixed(1)} GB';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showTvSwitcher(context, controller, onPair),
              child: Row(
                children: [
                  IconBadge(icon: Icons.tv, color: scheme.primary, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                controller.names[host] ??
                                    (info?.model.isNotEmpty == true
                                        ? info!.model
                                        : 'Sua TV'),
                                overflow: TextOverflow.ellipsis,
                                style: text.titleLarge,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            StatusDot(
                              color: online > 0 ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '$online de $total apps online · $host',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (info != null) ...[
              const SizedBox(height: 18),
              MeterBar(
                label: 'Memória em uso',
                value:
                    '${gb(info.ramTotalMb - info.ramFreeMb)} de '
                    '${gb(info.ramTotalMb)}',
                ratio: info.ramTotalMb == 0
                    ? 0
                    : 1 - info.ramFreeMb / info.ramTotalMb,
              ),
              const SizedBox(height: 12),
              MeterBar(
                label: 'Armazenamento em uso',
                value:
                    '${gb(info.diskTotalMb - info.diskFreeMb)} de '
                    '${gb(info.diskTotalMb)}',
                ratio: info.diskTotalMb == 0
                    ? 0
                    : 1 - info.diskFreeMb / info.diskTotalMb,
              ),
              const SizedBox(height: 10),
              Text(
                'Android ${info.android} · ligada há '
                '${info.uptimeSeconds ~/ 3600} h',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ] else if (!hasHub) ...[
              const SizedBox(height: 14),
              Text(
                'Falta o StickHub. Com ele você vê memória e disco, abre apps '
                'e instala APKs pela tela do celular.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Parear o StickHub'),
                onPressed: onPair,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({
    required this.enabled,
    required this.onClean,
    required this.onLink,
    required this.onInstall,
  });

  final bool enabled;
  final VoidCallback onClean;
  final VoidCallback onLink;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, VoidCallback action) {
      return Expanded(
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: enabled ? action : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        button(Icons.cleaning_services_outlined, 'Liberar RAM', onClean),
        const SizedBox(width: 10),
        button(Icons.link, 'Abrir link', onLink),
        const SizedBox(width: 10),
        button(Icons.upload_file, 'Instalar APK', onInstall),
      ],
    );
  }
}

class _TuneCard extends StatelessWidget {
  const _TuneCard({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: IconBadge(icon: Icons.speed, color: scheme.tertiary, size: 44),
        title: const Text('Otimizar a TV'),
        subtitle: const Text('Animações, menos lixo da Amazon, privacidade'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _InstallCard extends StatelessWidget {
  const _InstallCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: IconBadge(
          icon: Icons.system_update,
          color: scheme.secondary,
          size: 44,
        ),
        title: const Text('Instalar ou atualizar apps da TV'),
        subtitle: const Text('Pelo celular, sem PC'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _AppGrid extends StatelessWidget {
  const _AppGrid({required this.controller, required this.router});

  final HomeController controller;
  final RouterService router;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemCount: controller.current.length,
      itemBuilder: (context, index) {
        final endpoint = controller.current[index];
        final presence = controller.presence[endpoint.id] ?? Presence.checking;
        return _AppTile(
          endpoint: endpoint,
          presence: presence,
          onOpen: () {
            if (presence == Presence.offline) {
              showMessage(
                context,
                '${endpoint.kind.label} não responde. Abra o app na TV.',
              );
              return;
            }
            router.push<void>(
              context,
              '/${endpoint.kind.name}',
              args: endpoint,
            );
          },
          onRemove: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Remover ${endpoint.kind.label}?'),
                content: const Text(
                  'O token guardado neste celular será apagado.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Remover'),
                  ),
                ],
              ),
            );
            if (ok == true) {
              await controller.remove(endpoint);
            }
          },
        );
      },
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.endpoint,
    required this.presence,
    required this.onOpen,
    required this.onRemove,
  });

  final TvEndpoint endpoint;
  final Presence presence;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = endpoint.kind;
    final (label, color) = switch (presence) {
      Presence.online => ('online', Colors.green),
      Presence.offline => ('offline', Colors.redAccent),
      Presence.checking => ('verificando…', Colors.grey),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onRemove,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: kind.icon, color: kind.color, size: 42),
              const Spacer(),
              Text(
                kind.label,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  StatusDot(color: color, size: 8),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Onboarding extends StatelessWidget {
  const _Onboarding({required this.onScan, required this.onInstall});

  final VoidCallback onScan;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget step(int number, String title, String body) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Text('$number'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(body, style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        Icon(Icons.tv, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          'Vamos conectar sua TV',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        step(
          1,
          'Instale os apps na TV',
          'Ligue a Depuração ADB na TV e instale tudo daqui, pela rede, sem '
              'PC. Se o StickHub já estiver lá, pule este passo.',
        ),
        step(
          2,
          'Mostre o QR code',
          'Abra o StickHub e aperte MENU no controle.',
        ),
        step(
          3,
          'Escaneie aqui',
          'Um QR basta: os outros apps da TV são encontrados sozinhos.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('Instalar apps na TV'),
          onPressed: onInstall,
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Escanear QR code'),
          onPressed: onScan,
        ),
      ],
    );
  }
}

class _LinkSheet extends StatefulWidget {
  const _LinkSheet();

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Abrir link na TV',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'https://…'),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Enviar'),
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
          ),
        ],
      ),
    );
  }
}

void _showTvSwitcher(
  BuildContext context,
  HomeController controller,
  VoidCallback onAdd,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final host in controller.hosts)
            ListTile(
              leading: Icon(
                host == controller.currentHost
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(controller.nameOf(host)),
              subtitle: Text(
                '${controller.byHost[host]?.length ?? 0} apps · $host',
              ),
              onTap: () {
                Navigator.pop(sheet);
                controller.select(host);
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Adicionar outra TV'),
            onTap: () {
              Navigator.pop(sheet);
              onAdd();
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Renomear esta TV'),
            onTap: () {
              Navigator.pop(sheet);
              _renameTv(context, controller);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Remover esta TV'),
            onTap: () {
              Navigator.pop(sheet);
              _removeTv(context, controller);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _renameTv(BuildContext context, HomeController controller) async {
  final host = controller.currentHost;
  if (host == null) {
    return;
  }
  final field = TextEditingController(text: controller.names[host] ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Nome da TV'),
      content: TextField(
        controller: field,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Sala, Quarto…'),
        onSubmitted: (value) => Navigator.pop(dialog, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, field.text),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  field.dispose();
  if (name != null) {
    await controller.rename(host, name);
  }
}

Future<void> _removeTv(BuildContext context, HomeController controller) async {
  final host = controller.currentHost;
  if (host == null) {
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('Remover ${controller.nameOf(host)}?'),
      content: const Text(
        'Os apps e tokens dessa TV serão apagados deste celular.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Remover'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await controller.removeHost(host);
  }
}
