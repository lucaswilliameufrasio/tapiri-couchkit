import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/models/panel.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';

/// Abre um painel em tela cheia, com atualizacao automatica opcional.
class PanelViewPage extends StatefulWidget {
  const PanelViewPage({required this.panel, this.hub, super.key});

  static const route = '/panel';

  final Panel panel;
  final HubService? hub;

  @override
  State<PanelViewPage> createState() => _PanelViewPageState();
}

class _PanelViewPageState extends State<PanelViewPage> {
  late final WebViewController _web;
  Timer? _timer;
  int _progress = 0;

  Panel get _panel => widget.panel;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) {
              setState(() => _progress = value);
            }
          },
        ),
      );
    _load();
    if (_panel.refreshSeconds > 0) {
      _timer = Timer.periodic(
        Duration(seconds: _panel.refreshSeconds),
        (_) => _web.reload(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _load() {
    final uri = _panel.uri;
    if (uri != null) {
      _web.loadRequest(uri, headers: _panel.headers);
    }
  }

  Future<void> _sendToTv() async {
    final hub = widget.hub;
    final uri = _panel.uri;
    if (hub == null || uri == null) {
      showMessage(context, 'Pareie o StickHub para enviar à TV.');
      return;
    }
    await guarded(context, () => hub.openUrl(uri.toString()));
    if (!mounted) {
      return;
    }
    showMessage(
      context,
      _panel.headers.isEmpty
          ? 'Enviado ao navegador da TV'
          : 'Enviado. A TV abre sem o cabeçalho de autenticação.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_panel.name),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _web.reload,
          ),
          IconButton(
            tooltip: 'Mostrar na TV',
            icon: const Icon(Icons.cast),
            onPressed: _sendToTv,
          ),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: SafeArea(child: WebViewWidget(controller: _web)),
    );
  }
}
