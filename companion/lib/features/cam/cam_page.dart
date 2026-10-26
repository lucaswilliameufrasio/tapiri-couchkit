import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/services/cam_service.dart';

class CamPage extends StatefulWidget {
  const CamPage({required this.service, super.key});

  static const route = '/homecam';

  final CamService service;

  @override
  State<CamPage> createState() => _CamPageState();
}

class _CamPageState extends State<CamPage> {
  final _url = TextEditingController();
  CamConfig? _config;
  bool _busy = false;

  CamService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _apply(_service.get);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _apply(Future<CamConfig> Function() request) async {
    setState(() => _busy = true);
    final config = await guarded(context, request);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (config != null) {
        _config = config;
        _url.text = config.url;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('HomeCam')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Endereço do go2rtc que a TV usa para listar as câmeras.'),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'http://IP:1984'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _apply(() => _service.setUrl(_url.text)),
            child: Text(_busy ? 'Testando…' : 'Salvar e testar'),
          ),
          const SizedBox(height: 24),
          if (config != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          config.ok ? Icons.check_circle : Icons.error_outline,
                          color: config.ok ? Colors.green : Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          config.ok
                              ? '${config.cams.length} câmera(s) encontrada(s)'
                              : 'A TV não alcança esse endereço',
                        ),
                      ],
                    ),
                    for (final cam in config.cams)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.videocam_outlined),
                        title: Text(cam),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
