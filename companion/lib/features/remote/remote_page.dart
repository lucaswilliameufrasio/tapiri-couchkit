import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';
import 'package:couchkit_remote/data/tv_adb.dart';
import 'package:couchkit_remote/features/remote/dpad.dart';
import 'package:couchkit_remote/features/remote/remote_controller.dart';

/// Controle remoto da TV no celular (D-pad, voltar, home, midia, volume).
class RemotePage extends StatefulWidget {
  const RemotePage({
    required this.adb,
    required this.host,
    this.hub,
    super.key,
  });

  static const route = '/remote';

  final TvAdb adb;
  final String host;
  final HubService? hub;

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  late final RemoteController _controller = RemoteController(
    widget.adb,
    widget.host,
  )..addListener(_changed);
  int _tab = 0;
  List<InstalledApp>? _appList;

  @override
  void initState() {
    super.initState();
    _controller.connect();
    _loadApps();
  }

  Future<void> _loadApps() async {
    final hub = widget.hub;
    if (hub == null) {
      return;
    }
    final apps = await guarded(context, hub.apps);
    if (!mounted || apps == null) {
      return;
    }
    setState(() {
      _appList = [
        for (final app in apps)
          if (app.launchable && !app.system) app,
      ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    });
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

  void _press(RemoteKey key) {
    HapticFeedback.selectionClick();
    _controller.press(key);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Controle')),
      body: switch (controller.state) {
        RemoteState.ready => _pad(context),
        RemoteState.failed => _Message(
          icon: Icons.error_outline,
          text:
              '${controller.error}\nSe o ADB do PC estiver conectado, rode '
              '"adb disconnect": a TV aceita um cliente por vez.',
          action: FilledButton(
            onPressed: controller.connect,
            child: const Text('Tentar de novo'),
          ),
        ),
        RemoteState.waiting => const _Message(
          icon: Icons.tv,
          text: 'Aprove na TV: "Permitir depuração USB?" → "Sempre permitir".',
        ),
        RemoteState.connecting => const _Message(
          icon: Icons.sync,
          text: 'Conectando ao ADB da TV…',
        ),
      },
    );
  }

  Widget _pad(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget round(IconData icon, String label, VoidCallback onTap) {
      return IconButton.filled(
        tooltip: label,
        iconSize: 28,
        style: IconButton.styleFrom(
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(64, 64),
        ),
        icon: Icon(icon),
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            round(Icons.menu, 'Menu', () => _controller.press(RemoteKey.menu)),
            round(
              Icons.settings,
              'Configurações da TV',
              _controller.openSettings,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            IconButton(
              tooltip: 'Digitar na TV',
              icon: const Icon(Icons.keyboard),
              onPressed: _typeDialog,
            ),
            const Spacer(),
            PopupMenuButton<RemoteKey>(
              tooltip: 'Energia',
              icon: const Icon(Icons.power_settings_new),
              onSelected: _controller.press,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: RemoteKey.sleep,
                  child: Text('Pôr para dormir'),
                ),
                PopupMenuItem(value: RemoteKey.wakeup, child: Text('Acordar')),
              ],
            ),
          ],
        ),
        DPad(onPress: _press),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            round(
              Icons.keyboard_return,
              'Voltar',
              () => _controller.press(RemoteKey.back),
            ),
            IconButton.filled(
              tooltip: 'Início',
              iconSize: 28,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFE8602C),
                foregroundColor: Colors.white,
                minimumSize: const Size(64, 64),
              ),
              icon: const Icon(Icons.home_outlined),
              onPressed: () {
                HapticFeedback.selectionClick();
                _controller.press(RemoteKey.home);
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Mídia')),
            ButtonSegment(value: 1, label: Text('Aplicativos')),
          ],
          selected: {_tab},
          onSelectionChanged: (value) => setState(() => _tab = value.first),
        ),
        const SizedBox(height: 12),
        if (_tab == 0) _media(round) else _apps(),
      ],
    );
  }

  Widget _media(Widget Function(IconData, String, VoidCallback) round) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            round(
              Icons.fast_rewind,
              'Voltar',
              () => _controller.press(RemoteKey.rewind),
            ),
            round(
              Icons.play_arrow,
              'Reproduzir ou pausar',
              () => _controller.press(RemoteKey.playPause),
            ),
            round(
              Icons.fast_forward,
              'Avançar',
              () => _controller.press(RemoteKey.forward),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            round(
              Icons.volume_down,
              'Volume -',
              () => _controller.press(RemoteKey.volumeDown),
            ),
            round(
              Icons.volume_off,
              'Mudo',
              () => _controller.press(RemoteKey.mute),
            ),
            round(
              Icons.volume_up,
              'Volume +',
              () => _controller.press(RemoteKey.volumeUp),
            ),
          ],
        ),
      ],
    );
  }

  Widget _apps() {
    final hub = widget.hub;
    if (hub == null) {
      return const Text(
        'Instale e pareie o StickHub para ver seus apps aqui.',
        textAlign: TextAlign.center,
      );
    }
    final apps = _appList;
    if (apps == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        for (final app in apps)
          Tooltip(
            message: app.label,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => guarded(context, () => hub.launch(app.pkg)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: 96,
                  height: 54,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      hub.iconUri(app.pkg).toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Center(
                        child: Text(
                          app.label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _typeDialog() async {
    final field = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Digitar na TV'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(
            helperText: 'Letras, números e . _ @ -',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    field.dispose();
    if (text != null) {
      _controller.type(text);
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
