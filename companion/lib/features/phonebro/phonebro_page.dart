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
    super.key,
  });

  static const route = '/phonebro';

  final PhoneBroService service;
  final TvEndpoint endpoint;

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
    if (state != null && mounted) {
      setState(() {
        _url.text = state.url;
        _title = state.title;
      });
    }
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
