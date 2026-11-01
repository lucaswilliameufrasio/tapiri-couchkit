import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/services/phonebro_service.dart';

class PhoneBroPage extends StatefulWidget {
  const PhoneBroPage({
    required this.service,
    required this.endpoint,
    this.openApp,
    super.key,
  });

  static const route = '/phonebro';

  final PhoneBroService service;
  final TvEndpoint endpoint;

  /// Abre o PhoneBro na TV (pelo StickHub) quando ele nao responde.
  final Future<void> Function()? openApp;

  @override
  State<PhoneBroPage> createState() => _PhoneBroPageState();
}

class _PhoneBroPageState extends State<PhoneBroPage> {
  static const _keyEnter = 66;
  static const _keyBackspace = 67;

  final _url = TextEditingController();
  final _text = TextEditingController();
  Timer? _flush;
  double _dx = 0;
  double _dy = 0;
  String _title = '';
  bool _offline = false;

  PhoneBroService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _flush = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => _sendMove(),
    );
    _loadState();
  }

  @override
  void dispose() {
    _flush?.cancel();
    _url.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final state = await guarded(context, _service.state);
    if (!mounted) {
      return;
    }
    setState(() {
      _offline = state == null;
      if (state != null) {
        _url.text = state.url;
        _title = state.title;
      }
    });
  }

  Future<void> _open() async {
    final open = widget.openApp;
    if (open == null) {
      return;
    }
    await guarded(context, open);
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) {
      await _loadState();
    }
  }

  Future<void> _showBookmarks() async {
    final state = await guarded(context, _service.state);
    if (state == null || !mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => _BookmarksSheet(
        service: _service,
        initial: state.bookmarks,
        onOpen: (url) {
          Navigator.of(sheet).pop();
          _tap(() => _service.navigate(url));
        },
      ),
    );
  }

  void _sendMove() {
    if (_dx.abs() < 0.5 && _dy.abs() < 0.5) {
      return;
    }
    final dx = _dx;
    final dy = _dy;
    _dx = 0;
    _dy = 0;
    unawaited(_service.move(dx, dy).catchError((Object _) {}));
  }

  void _tap(Future<void> Function() action) {
    HapticFeedback.selectionClick();
    guarded(context, action);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title.isEmpty ? 'PhoneBro' : _title, maxLines: 1),
        actions: [
          IconButton(
            tooltip: 'Favoritos',
            icon: const Icon(Icons.star_outline),
            onPressed: _showBookmarks,
          ),
          IconButton(
            tooltip: 'Diminuir zoom',
            icon: const Icon(Icons.zoom_out),
            onPressed: () => _tap(() => _service.zoom(0.8)),
          ),
          IconButton(
            tooltip: 'Aumentar zoom',
            icon: const Icon(Icons.zoom_in),
            onPressed: () => _tap(() => _service.zoom(1.25)),
          ),
          IconButton(
            tooltip: 'Alternar modo desktop',
            icon: const Icon(Icons.desktop_windows_outlined),
            onPressed: () => _tap(_service.toggleDesktopMode),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (_offline && widget.openApp != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.power_settings_new),
                    title: const Text('O PhoneBro não está aberto na TV'),
                    trailing: FilledButton(
                      onPressed: _open,
                      child: const Text('Abrir'),
                    ),
                  ),
                ),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Endereço ou busca',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => _tap(() => _service.navigate(_url.text)),
                  ),
                ),
                onSubmitted: (value) => _tap(() => _service.navigate(value)),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _icon(Icons.arrow_back, 'Voltar', _service.back),
                  _icon(Icons.arrow_forward, 'Avançar', _service.forward),
                  _icon(Icons.refresh, 'Recarregar', _service.reload),
                  _icon(Icons.home_outlined, 'Início', _service.home),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(child: _touchpad(context)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      decoration: const InputDecoration(
                        labelText: 'Digitar na TV',
                        isDense: true,
                      ),
                      onChanged: (value) => unawaited(
                        _service.text(value).catchError((Object _) {}),
                      ),
                      onSubmitted: (_) => _tap(() => _service.key(_keyEnter)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Apagar',
                    icon: const Icon(Icons.backspace_outlined),
                    onPressed: () => _tap(() => _service.key(_keyBackspace)),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Enter',
                    icon: const Icon(Icons.keyboard_return),
                    onPressed: () => _tap(() => _service.key(_keyEnter)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _icon(
                    Icons.replay_10,
                    '-10 s',
                    () => _service.mediaSeek(-10),
                  ),
                  _icon(Icons.play_arrow, 'Play/pausa', _service.mediaToggle),
                  _icon(
                    Icons.forward_10,
                    '+10 s',
                    () => _service.mediaSeek(10),
                  ),
                  _icon(
                    Icons.volume_down,
                    'Volume -',
                    () => _service.volume(-1),
                  ),
                  _icon(Icons.volume_up, 'Volume +', () => _service.volume(1)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _icon(IconData icon, String tooltip, Future<void> Function() action) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: () => _tap(action),
    );
  }

  Widget _touchpad(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tap(_service.click),
            onPanUpdate: (details) {
              _dx += details.delta.dx * 1.8;
              _dy += details.delta.dy * 1.8;
            },
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                'Toque para clicar\narraste para mover o cursor',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            unawaited(
              _service.scroll(-details.delta.dy * 3).catchError((Object _) {}),
            );
          },
          child: Container(
            width: 56,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: const RotatedBox(quarterTurns: 3, child: Text('rolar')),
          ),
        ),
      ],
    );
  }
}

class _BookmarksSheet extends StatefulWidget {
  const _BookmarksSheet({
    required this.service,
    required this.initial,
    required this.onOpen,
  });

  final PhoneBroService service;
  final List<Bookmark> initial;
  final void Function(String url) onOpen;

  @override
  State<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<_BookmarksSheet> {
  late List<Bookmark> _marks = List.of(widget.initial);

  Future<void> _reload() async {
    final state = await guarded(context, widget.service.state);
    if (state != null && mounted) {
      setState(() => _marks = state.bookmarks);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Favoritar a página aberta na TV'),
              onTap: () async {
                await guarded(context, widget.service.addBookmark);
                await _reload();
              },
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final mark in _marks)
                    ListTile(
                      title: Text(mark.title, maxLines: 1),
                      subtitle: Text(mark.url, maxLines: 1),
                      onTap: () => widget.onOpen(mark.url),
                      trailing: IconButton(
                        tooltip: 'Remover',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await guarded(
                            context,
                            () => widget.service.removeBookmark(mark.url),
                          );
                          await _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
