import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:couchkit_remote/data/services/hub_service.dart';

/// Perfis de otimizacao que o StickHub sabe aplicar pelo ADB local.
class TuneProfile {
  const TuneProfile({
    required this.id,
    required this.undoId,
    required this.title,
    required this.description,
  });

  final String id;
  final String undoId;
  final String title;
  final String description;
}

const tuneProfiles = [
  TuneProfile(
    id: 'animacoes',
    undoId: 'animacoes-off',
    title: 'Animações rápidas',
    description: 'Transições do sistema em 0,5x: a TV parece mais ágil.',
  ),
  TuneProfile(
    id: 'debloat',
    undoId: 'debloat-off',
    title: 'Menos lixo da Amazon',
    description:
        'Desativa 21 apps de anúncios, métricas e serviços que você não usa. '
        'Dá para desfazer.',
  ),
  TuneProfile(
    id: 'privacidade',
    undoId: 'privacidade-off',
    title: 'Privacidade',
    description: 'Limita anúncios personalizados e o envio de dados de uso.',
  ),
];

class TuneController extends ChangeNotifier {
  TuneController(this._service);

  final HubService _service;

  TuneStatus status = const TuneStatus(adb: 'idle', tune: '');
  String? error;
  Timer? _poll;

  Future<void> refresh() async {
    try {
      status = await _service.tuneStatus();
      error = null;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  /// Conecta no ADB da TV e acompanha ate autorizar (ou falhar).
  Future<void> connect() async {
    await _service.adbConnect();
    _startPolling();
    await refresh();
  }

  /// Roda um perfil e acompanha o progresso.
  Future<bool> run(String profile) async {
    final started = await _service.tune(profile);
    _startPolling();
    await refresh();
    return started;
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      await refresh();
      final idle = !status.waiting && !status.running;
      if (idle) {
        _poll?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
