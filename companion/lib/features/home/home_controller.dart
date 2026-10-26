import 'package:flutter/foundation.dart';

import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/tv_repository.dart';

enum Presence { checking, online, offline }

class HomeController extends ChangeNotifier {
  HomeController(this._repository);

  final TvRepository _repository;

  List<TvEndpoint> endpoints = [];
  final Map<String, Presence> presence = {};
  bool loading = true;

  Future<void> load() async {
    endpoints = await _repository.load();
    loading = false;
    notifyListeners();
    await refresh();
  }

  /// Confere cada app; se estiver fora do ar, tenta reencontrar a porta.
  Future<void> refresh() async {
    for (final endpoint in endpoints) {
      presence[endpoint.id] = Presence.checking;
    }
    notifyListeners();
    final checks = <Future<void>>[];
    for (final endpoint in List.of(endpoints)) {
      checks.add(_check(endpoint));
    }
    await Future.wait(checks);
  }

  Future<void> _check(TvEndpoint endpoint) async {
    var current = endpoint;
    var online = await _repository.isOnline(current);
    if (!online) {
      final moved = await _repository.relocate(current);
      if (moved != null) {
        current = moved;
        online = true;
        _replace(moved);
      }
    }
    presence[current.id] = online ? Presence.online : Presence.offline;
    notifyListeners();
  }

  void _replace(TvEndpoint moved) {
    final next = <TvEndpoint>[];
    for (final item in endpoints) {
      next.add(item.id == moved.id ? moved : item);
    }
    endpoints = next;
  }

  Future<TvEndpoint> pair(String url) async {
    final endpoint = await _repository.pair(url);
    endpoints = await _repository.load();
    presence[endpoint.id] = Presence.online;
    notifyListeners();
    return endpoint;
  }

  Future<void> remove(TvEndpoint endpoint) async {
    await _repository.remove(endpoint.id);
    endpoints = await _repository.load();
    presence.remove(endpoint.id);
    notifyListeners();
  }

  /// Endpoints agrupados por host (uma TV).
  Map<String, List<TvEndpoint>> get byHost {
    final groups = <String, List<TvEndpoint>>{};
    for (final endpoint in endpoints) {
      groups.putIfAbsent(endpoint.host, () => []).add(endpoint);
    }
    return groups;
  }
}
