import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';

class HubPage extends StatefulWidget {
  const HubPage({required this.service, super.key});

  static const route = '/stickhub';

  final HubService service;

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  List<InstalledApp> _apps = [];
  DeviceInfo? _info;
  bool _loading = true;
  bool _showSystem = false;
  String _filter = '';
  double? _progress;
  final _link = TextEditingController();

  HubService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final apps = await guarded(context, _service.apps);
    if (!mounted) {
      return;
    }
    final info = await guarded(context, _service.info);
    if (!mounted) {
      return;
    }
    setState(() {
      _apps = apps ?? _apps;
      _info = info ?? _info;
      _loading = false;
    });
  }

  Future<void> _installApk() async {
    final picked = await FilePicker.pickFile();
    final path = picked?.path;
    if (path == null || !mounted) {
      return;
    }
    if (!path.toLowerCase().endsWith('.apk')) {
      showMessage(context, 'Escolha um arquivo .apk');
      return;
    }
    setState(() => _progress = 0);
    final message = await guarded(
      context,
      () => _service.installApk(
        File(path),
        onProgress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => _progress = sent / total);
          }
        },
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _progress = null);
    if (message != null) {
      showMessage(
        context,
        message.isEmpty ? 'Enviado. Confirme a instalação na TV.' : message,
      );
    }
  }

  Future<void> _act(Future<String> Function() action) async {
    final message = await guarded(context, action);
    if (mounted && message != null && message.isNotEmpty) {
      showMessage(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = <InstalledApp>[];
    for (final app in _apps) {
      final matches =
          _filter.isEmpty ||
          app.label.toLowerCase().contains(_filter) ||
          app.pkg.toLowerCase().contains(_filter);
      if (matches && (_showSystem || !app.system)) {
        visible.add(app);
      }
    }
    visible.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('StickHub'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Apps'),
              Tab(text: 'Sistema'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Instalar APK',
              icon: const Icon(Icons.upload_file),
              onPressed: _progress == null ? _installApk : null,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_progress != null) LinearProgressIndicator(value: _progress),
            Expanded(
              child: TabBarView(
                children: [_appsTab(visible), _systemTab(context)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appsTab(List<InstalledApp> visible) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar app',
              isDense: true,
            ),
            onChanged: (value) => setState(() => _filter = value.toLowerCase()),
          ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Mostrar apps do sistema'),
          value: _showSystem,
          onChanged: (value) => setState(() => _showSystem = value),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) => _appTile(visible[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _appTile(InstalledApp app) {
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: Image.network(
          _service.iconUri(app.pkg).toString(),
          errorBuilder: (context, error, stack) => const Icon(Icons.android),
        ),
      ),
      title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(app.pkg, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: app.launchable ? () => _act(() => _service.launch(app.pkg)) : null,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'stop':
              _act(() => _service.stop(app.pkg));
            case 'details':
              _act(() => _service.details(app.pkg));
            case 'uninstall':
              _act(() => _service.uninstall(app.pkg));
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'stop', child: Text('Encerrar')),
          const PopupMenuItem(value: 'details', child: Text('Detalhes na TV')),
          if (!app.system)
            const PopupMenuItem(value: 'uninstall', child: Text('Desinstalar')),
        ],
      ),
    );
  }

  Widget _systemTab(BuildContext context) {
    final info = _info;
    if (info == null) {
      return const Center(child: Text('Sem dados do aparelho'));
    }
    String gb(int mb) => '${(mb / 1024).toStringAsFixed(1)} GB';
    final hours = info.uptimeSeconds ~/ 3600;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.model,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Android ${info.android} · ligado há ${hours}h'),
                const SizedBox(height: 16),
                _meter('RAM livre', info.ramFreeMb, info.ramTotalMb, gb),
                const SizedBox(height: 12),
                _meter(
                  'Armazenamento livre',
                  info.diskFreeMb,
                  info.diskTotalMb,
                  gb,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('Liberar RAM'),
          onPressed: () async {
            await guarded(context, _service.clean);
            await _load();
          },
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Abrir link no navegador da TV',
            suffixIcon: IconButton(
              icon: const Icon(Icons.send),
              onPressed: () =>
                  guarded(context, () => _service.openUrl(_link.text)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _meter(String label, int free, int total, String Function(int) fmt) {
    final ratio = total == 0 ? 0.0 : free / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${fmt(free)} de ${fmt(total)}'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: ratio, minHeight: 8),
      ],
    );
  }
}
