import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/core/ui/widgets.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';
import 'package:couchkit_remote/features/hub/install_flow.dart';

/// Todos os apps instalados na TV; um toque abre o app la.
class LauncherTab extends StatefulWidget {
  const LauncherTab({
    required this.hub,
    required this.endpoint,
    required this.onPair,
    super.key,
  });

  final HubService? hub;
  final TvEndpoint? endpoint;
  final VoidCallback onPair;

  @override
  State<LauncherTab> createState() => _LauncherTabState();
}

enum _Filter { mine, all }

class _LauncherTabState extends State<LauncherTab> {
  List<InstalledApp> _apps = [];
  bool _loading = false;
  _Filter _filter = _Filter.mine;
  String _query = '';
  double? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LauncherTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endpoint != widget.endpoint) {
      _load();
    }
  }

  Future<void> _load() async {
    final hub = widget.hub;
    if (hub == null) {
      return;
    }
    setState(() => _loading = true);
    final apps = await guarded(context, hub.apps);
    if (mounted) {
      setState(() {
        _apps = apps ?? _apps;
        _loading = false;
      });
    }
  }

  Future<void> _open(InstalledApp app) async {
    HapticFeedback.selectionClick();
    final message = await guarded(context, () => widget.hub!.launch(app.pkg));
    if (!mounted) {
      return;
    }
    if (message != null) {
      showMessage(
        context,
        message.isEmpty ? 'Abrindo ${app.label} na TV' : message,
      );
    }
  }

  Future<void> _install() async {
    final hub = widget.hub;
    if (hub == null) {
      return;
    }
    final ok = await installApkFlow(
      context,
      hub,
      onProgress: (value) {
        if (mounted) {
          setState(() => _progress = value);
        }
      },
    );
    if (ok) {
      await _load();
    }
  }

  List<InstalledApp> get _visible {
    final result = <InstalledApp>[];
    for (final app in _apps) {
      final matches =
          _query.isEmpty ||
          app.label.toLowerCase().contains(_query) ||
          app.pkg.toLowerCase().contains(_query);
      final scope = app.launchable && (_filter == _Filter.all || !app.system);
      if (matches && scope) {
        result.add(app);
      }
    }
    result.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return result;
  }

  void _menu(InstalledApp app) {
    final hub = widget.hub!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                app.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(app.pkg),
            ),
            ListTile(
              leading: const Icon(Icons.stop_circle_outlined),
              title: const Text('Encerrar'),
              onTap: () {
                Navigator.pop(sheet);
                guarded(context, () => hub.stop(app.pkg));
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Detalhes na TV'),
              onTap: () {
                Navigator.pop(sheet);
                guarded(context, () => hub.details(app.pkg));
              },
            ),
            if (!app.system)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Desinstalar'),
                onTap: () {
                  Navigator.pop(sheet);
                  guarded(context, () => hub.uninstall(app.pkg));
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hub = widget.hub;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps da TV'),
        actions: [
          IconButton(
            tooltip: 'Instalar APK na TV',
            icon: const Icon(Icons.upload_file),
            onPressed: hub == null || _progress != null ? null : _install,
          ),
        ],
      ),
      body: hub == null
          ? EmptyPane(
              icon: Icons.apps,
              title: 'Pareie o StickHub',
              message:
                  'O StickHub lista e abre os apps da TV. Escaneie o QR '
                  'dele para ver tudo aqui.',
              action: FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Escanear QR'),
                onPressed: widget.onPair,
              ),
            )
          : Column(
              children: [
                if (_progress != null)
                  LinearProgressIndicator(value: _progress),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar app',
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.toLowerCase()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Meus apps'),
                        selected: _filter == _Filter.mine,
                        onSelected: (_) =>
                            setState(() => _filter = _Filter.mine),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Todos'),
                        selected: _filter == _Filter.all,
                        onSelected: (_) =>
                            setState(() => _filter = _Filter.all),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _grid(hub)),
              ],
            ),
    );
  }

  Widget _grid(HubService hub) {
    if (_loading && _apps.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final apps = _visible;
    return RefreshIndicator(
      onRefresh: _load,
      child: apps.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                EmptyPane(
                  icon: Icons.search_off,
                  title: 'Nada por aqui',
                  message: 'Nenhum app combina com o filtro.',
                ),
              ],
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 4,
                childAspectRatio: 0.78,
              ),
              itemCount: apps.length,
              itemBuilder: (context, index) {
                final app = apps[index];
                return _AppCell(
                  app: app,
                  iconUrl: hub.iconUri(app.pkg).toString(),
                  onTap: app.launchable ? () => _open(app) : null,
                  onLongPress: () => _menu(app),
                );
              },
            ),
    );
  }
}

class _AppCell extends StatelessWidget {
  const _AppCell({
    required this.app,
    required this.iconUrl,
    required this.onTap,
    required this.onLongPress,
  });

  final InstalledApp app;
  final String iconUrl;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Image.network(
                  iconUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 112,
                  errorBuilder: (context, error, stack) => ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.apps, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              app.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}
