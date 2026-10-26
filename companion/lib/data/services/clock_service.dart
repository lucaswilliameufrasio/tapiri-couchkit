import 'package:couchkit_remote/core/network/tv_client.dart';

class ClockNote {
  const ClockNote({required this.done, required this.text});

  final bool done;
  final String text;
}

class ClockData {
  const ClockData({required this.city, required this.notes});

  final String city;
  final List<ClockNote> notes;
}

class ClockService {
  ClockService(this._client);

  final TvClient _client;

  Future<ClockData> get() async {
    final json = await _client.getJson('/api/get');
    final notes = <ClockNote>[];
    final raw = json['notes'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          notes.add(
            ClockNote(done: item['done'] == true, text: '${item['t']}'),
          );
        }
      }
    }
    return ClockData(city: '${json['city'] ?? ''}', notes: notes);
  }

  /// Retorna o nome resolvido da cidade, ou lanca se nao achou.
  Future<String> setCity(String query) async {
    final json = await _client.getJson('/api/city', {'q': query});
    return '${json['msg'] ?? ''}';
  }

  Future<void> add(String text) => _client.getJson('/api/add', {'t': text});

  Future<void> toggle(int index) {
    return _client.getJson('/api/toggle', {'i': '$index'});
  }

  Future<void> remove(int index) {
    return _client.getJson('/api/del', {'i': '$index'});
  }

  Future<void> clearDone() => _client.getJson('/api/clear');
}
