import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couchkit_remote/data/tv_adb.dart';
import 'package:couchkit_remote/features/remote/remote_controller.dart';

/// Controle remoto da TV no celular (D-pad, voltar, home, midia, volume).
class RemotePage extends StatefulWidget {
  const RemotePage({required this.adb, required this.host, super.key});

  static const route = '/remote';

  final TvAdb adb;
  final String host;

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  late final RemoteController _controller = RemoteController(
    widget.adb,
    widget.host,
  )..addListener(_changed);
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.connect();
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
    _text.dispose();
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
    Widget key(
      RemoteKey remoteKey,
      IconData icon,
      String label, {
      bool primary = false,
    }) {
      final style = primary
          ? IconButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            )
          : IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh);
      return IconButton(
        tooltip: label,
        iconSize: 30,
        style: style,
        constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
        icon: Icon(icon),
        onPressed: () => _press(remoteKey),
      );
    }

    const gap = SizedBox(width: 10, height: 10);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Column(
            children: [
              key(RemoteKey.up, Icons.keyboard_arrow_up, 'Cima'),
              gap,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  key(RemoteKey.left, Icons.keyboard_arrow_left, 'Esquerda'),
                  gap,
                  key(RemoteKey.ok, Icons.circle, 'OK', primary: true),
                  gap,
                  key(RemoteKey.right, Icons.keyboard_arrow_right, 'Direita'),
                ],
              ),
              gap,
              key(RemoteKey.down, Icons.keyboard_arrow_down, 'Baixo'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            key(RemoteKey.back, Icons.arrow_back, 'Voltar'),
            key(RemoteKey.home, Icons.home_outlined, 'Início'),
            key(RemoteKey.menu, Icons.menu, 'Menu'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            key(RemoteKey.rewind, Icons.fast_rewind, 'Voltar 10s'),
            key(RemoteKey.playPause, Icons.play_arrow, 'Reproduzir/pausar'),
            key(RemoteKey.forward, Icons.fast_forward, 'Avançar'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            key(RemoteKey.volumeDown, Icons.volume_down, 'Volume -'),
            key(RemoteKey.mute, Icons.volume_off, 'Mudo'),
            key(RemoteKey.volumeUp, Icons.volume_up, 'Volume +'),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _text,
          decoration: InputDecoration(
            labelText: 'Digitar na TV',
            helperText: 'Letras, números e . _ @ -',
            suffixIcon: IconButton(
              tooltip: 'Enviar',
              icon: const Icon(Icons.send),
              onPressed: () {
                _controller.type(_text.text);
                _text.clear();
              },
            ),
          ),
          onSubmitted: (value) {
            _controller.type(value);
            _text.clear();
          },
        ),
      ],
    );
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
