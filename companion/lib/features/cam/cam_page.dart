import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/core/ui/widgets.dart';
import 'package:couchkit_remote/data/models/cam_config.dart';
import 'package:couchkit_remote/data/services/cam_service.dart';
import 'package:couchkit_remote/features/cam/cam_controller.dart';

/// Configura o HomeCam: servidores go2rtc (com senha), cameras RTSP/RTMP,
/// ordem, nomes e colunas da grade.
class CamPage extends StatefulWidget {
  const CamPage({required this.service, super.key});

  static const route = '/homecam';

  final CamService service;

  @override
  State<CamPage> createState() => _CamPageState();
}

class _CamPageState extends State<CamPage> {
  late final CamController _controller = CamController(widget.service)
    ..addListener(_changed);

  @override
  void initState() {
    super.initState();
    guarded(context, _controller.load);
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
    super.dispose();
  }

  Future<void> _do(Future<void> Function() action) async {
    await guarded(context, action);
  }

  Future<void> _editServer([CamServerConfig? server]) async {
    final result = await showDialog<CamServerConfig>(
      context: context,
      builder: (context) => _ServerDialog(
        server: server,
        create: (name, url, user, pass) =>
            _controller.newServer(name: name, url: url, user: user, pass: pass),
      ),
    );
    if (result != null) {
      await _do(() => _controller.saveServer(result));
    }
  }

  Future<void> _addCamera() async {
    final result = await showDialog<_NewCamera>(
      context: context,
      builder: (context) =>
          _CameraDialog(servers: _controller.settings.servers),
    );
    if (result != null) {
      await _do(
        () => _controller.addCamera(
          name: result.name,
          src: result.src,
          serverId: result.serverId,
        ),
      );
    }
  }

  Future<void> _rename(CamEntry entry) async {
    final field = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nome da câmera'),
        content: TextField(controller: field, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    field.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await _do(() => _controller.rename(entry, name));
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
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
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('HomeCam')),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                if (controller.busy) const LinearProgressIndicator(),
                const SectionTitle('Servidores go2rtc'),
                if (controller.settings.servers.isEmpty)
                  Text(
                    'Adicione o endereço do go2rtc (ex.: http://192.168.0.10:1984). '
                    'Pode ter vários, cada um com usuário e senha.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                for (final server in controller.settings.servers)
                  _ServerTile(
                    server: server,
                    error: controller.listing.errors[server.name],
                    onEdit: () => _editServer(server),
                    onRemove: () async {
                      if (await _confirm(
                        'Remover ${server.name}?',
                        'As câmeras deste servidor somem da TV. Nada é '
                            'apagado no go2rtc.',
                      )) {
                        await _do(() => controller.removeServer(server.id));
                      }
                    },
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.dns_outlined),
                  label: const Text('Adicionar servidor'),
                  onPressed: _editServer,
                ),
                const SectionTitle('Câmeras'),
                if (controller.listing.cams.isEmpty)
                  Text(
                    'Nenhuma câmera ainda.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  )
                else
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorderItem: (from, to) =>
                        _do(() => controller.reorder(from, to)),
                    children: [
                      for (final entry in controller.listing.cams)
                        _CamTile(
                          key: ValueKey(entry.key),
                          entry: entry,
                          source: entry.direct
                              ? 'RTSP direto na TV'
                              : controller.serverName(entry.serverId),
                          onRename: () => _rename(entry),
                          onToggle: () =>
                              _do(() => controller.toggleHidden(entry)),
                          onRemove: () async {
                            if (await _confirm(
                              'Remover ${entry.name}?',
                              entry.direct
                                  ? 'A câmera sai da TV.'
                                  : 'Também apaga a câmera do go2rtc.',
                            )) {
                              await _do(() => controller.removeCamera(entry));
                            }
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Adicionar câmera'),
                  onPressed: _addCamera,
                ),
                const SectionTitle('Grade na TV'),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 2, label: Text('2 colunas')),
                    ButtonSegment(value: 3, label: Text('3 colunas')),
                    ButtonSegment(value: 4, label: Text('4 colunas')),
                  ],
                  selected: {controller.settings.cols},
                  onSelectionChanged: (value) =>
                      _do(() => controller.setCols(value.first)),
                ),
              ],
            ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.error,
    required this.onEdit,
    required this.onRemove,
  });

  final CamServerConfig server;
  final String? error;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: Icon(
          error == null ? Icons.check_circle : Icons.error_outline,
          color: error == null ? Colors.green : scheme.error,
        ),
        title: Text(server.name),
        subtitle: Text(
          error ?? '${server.url}${server.hasAuth ? ' · com senha' : ''}',
        ),
        onTap: onEdit,
        trailing: IconButton(
          tooltip: 'Remover',
          icon: const Icon(Icons.delete_outline),
          onPressed: onRemove,
        ),
      ),
    );
  }
}

class _CamTile extends StatelessWidget {
  const _CamTile({
    required this.entry,
    required this.source,
    required this.onRename,
    required this.onToggle,
    required this.onRemove,
    super.key,
  });

  final CamEntry entry;
  final String source;
  final VoidCallback onRename;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 4, right: 0),
      leading: Icon(
        entry.direct ? Icons.videocam_outlined : Icons.camera_outdoor_outlined,
        color: entry.hidden ? muted : null,
      ),
      title: Text(
        entry.name,
        style: TextStyle(
          color: entry.hidden ? muted : null,
          decoration: entry.hidden ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(source),
      onTap: onRename,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: entry.hidden ? 'Mostrar na TV' : 'Ocultar da TV',
            icon: Icon(entry.hidden ? Icons.visibility_off : Icons.visibility),
            onPressed: onToggle,
          ),
          IconButton(
            tooltip: 'Remover',
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog({required this.server, required this.create});

  final CamServerConfig? server;
  final CamServerConfig Function(
    String name,
    String url,
    String user,
    String pass,
  )
  create;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _name = TextEditingController(text: widget.server?.name ?? '');
  late final _url = TextEditingController(text: widget.server?.url ?? '');
  late final _user = TextEditingController(text: widget.server?.user ?? '');
  late final _pass = TextEditingController(text: widget.server?.pass ?? '');

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    if (url.isEmpty) {
      return;
    }
    final name = _name.text.trim().isEmpty ? 'go2rtc' : _name.text.trim();
    final existing = widget.server;
    Navigator.pop(
      context,
      existing == null
          ? widget.create(name, url, _user.text.trim(), _pass.text)
          : CamServerConfig(
              id: existing.id,
              name: name,
              url: url,
              user: _user.text.trim(),
              pass: _pass.text,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.server == null ? 'Novo servidor' : 'Servidor'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome (ex.: Casa)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Endereço',
                hintText: 'http://192.168.0.10:1984',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _user,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Usuário (se tiver senha)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Salvar')),
      ],
    );
  }
}

class _NewCamera {
  const _NewCamera(this.name, this.src, this.serverId);

  final String name;
  final String src;
  final String? serverId;
}

class _CameraDialog extends StatefulWidget {
  const _CameraDialog({required this.servers});

  final List<CamServerConfig> servers;

  @override
  State<_CameraDialog> createState() => _CameraDialogState();
}

class _CameraDialogState extends State<_CameraDialog> {
  final _name = TextEditingController();
  final _src = TextEditingController();
  late String? _server = widget.servers.isEmpty
      ? null
      : widget.servers.first.id;

  @override
  void dispose() {
    _name.dispose();
    _src.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova câmera'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _src,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Endereço da câmera',
                hintText: 'rtsp://usuario:senha@192.168.0.5/stream',
                helperText: 'rtsp://, rtmp://, http:// ou ffmpeg:...',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _server,
              decoration: const InputDecoration(labelText: 'Onde cadastrar'),
              items: [
                for (final server in widget.servers)
                  DropdownMenuItem(
                    value: server.id,
                    child: Text('go2rtc · ${server.name}'),
                  ),
                const DropdownMenuItem(
                  value: null,
                  child: Text('Direto na TV (só RTSP)'),
                ),
              ],
              onChanged: (value) => setState(() => _server = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final src = _src.text.trim();
            if (name.isEmpty || src.isEmpty) {
              return;
            }
            Navigator.pop(context, _NewCamera(name, src, _server));
          },
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
