import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/tv_launcher.dart';

/// Escolhe o launcher que o botao Home da TV abre.
class LauncherPage extends StatefulWidget {
  const LauncherPage({required this.launcher, required this.host, super.key});

  static const route = '/launcher';

  final TvLauncher launcher;
  final String host;

  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

class _LauncherPageState extends State<LauncherPage> {
  LauncherState? _state;
  String? _error;
  bool _busy = true;
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await widget.launcher.load(
        widget.host,
        onWaitingApproval: () {
          if (mounted) {
            setState(() => _waiting = true);
          }
        },
      );
      if (mounted) {
        setState(() => _state = state);
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waiting = false;
        });
      }
    }
  }

  Future<void> _choose(HomeApp app) async {
    setState(() => _busy = true);
    try {
      final ok = await widget.launcher.set(widget.host, app.component);
      if (mounted) {
        showMessage(
          context,
          ok
              ? 'Pronto: o botão Home abre ${_label(app)}.'
              : 'A TV não aderiu à troca (o launcher do fabricante pode '
                    'ignorá-la).',
        );
      }
    } on AppException catch (e) {
      if (mounted) {
        showMessage(context, e.message);
      }
    }
    await _load();
  }

  static String _label(HomeApp app) {
    return switch (app.pkg) {
      'com.lucas.firehome' => 'FireHome',
      'com.google.android.tvlauncher' => 'Launcher do Android TV',
      'com.google.android.apps.tv.launcherx' => 'Launcher do Google TV',
      _ => app.pkg,
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    String? current;
    if (state != null) {
      for (final app in state.apps) {
        if (app.current) {
          current = app.component;
        }
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Tela inicial padrão')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_waiting)
            const ListTile(
              leading: Icon(Icons.tv, color: Colors.orange),
              title: Text('Aprove na TV: "Sempre permitir".'),
            ),
          if (_error != null)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(_error!),
              trailing: TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Tentar de novo'),
              ),
            ),
          if (state != null && !state.supported)
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Esta TV não permite trocar a tela inicial'),
              subtitle: Text(
                'Fire OS 5 e Android 8 ou anterior protegem o launcher. No '
                'Fire TV Stick, o FireHome abre pelo ícone dele.',
              ),
            ),
          if (state != null && state.supported)
            RadioGroup<String>(
              groupValue: current,
              onChanged: (value) {
                if (_busy || value == null) {
                  return;
                }
                for (final app in state.apps) {
                  if (app.component == value) {
                    _choose(app);
                  }
                }
              },
              child: Column(
                children: [
                  for (final app in state.apps)
                    RadioListTile<String>(
                      value: app.component,
                      title: Text(_label(app)),
                      subtitle: Text(app.component),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
