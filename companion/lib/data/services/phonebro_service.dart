import 'package:couchkit_remote/core/network/tv_client.dart';

class BrowserState {
  const BrowserState({required this.url, required this.title});

  final String url;
  final String title;
}

class PhoneBroService {
  PhoneBroService(this._client);

  final TvClient _client;

  Future<BrowserState> state() async {
    final json = await _client.getJson('/api/state');
    return BrowserState(
      url: '${json['url'] ?? ''}',
      title: '${json['title'] ?? ''}',
    );
  }

  Future<void> navigate(String url) => _call('nav', {'url': url});

  Future<void> back() => _call('back');

  Future<void> forward() => _call('forward');

  Future<void> reload() => _call('reload');

  Future<void> home() => _call('home');

  Future<void> click() => _call('click');

  Future<void> move(double dx, double dy) {
    return _call('move', {
      'dx': dx.toStringAsFixed(1),
      'dy': dy.toStringAsFixed(1),
    });
  }

  Future<void> scroll(double dy) {
    return _call('scroll', {'dy': dy.toStringAsFixed(1)});
  }

  Future<void> text(String value) => _call('text', {'t': value});

  /// Codigo de tecla Android (ex.: 66 = Enter, 67 = Backspace).
  Future<void> key(int code) => _call('key', {'code': '$code'});

  Future<void> mediaToggle() => _call('media', {'a': 'toggle'});

  Future<void> mediaSeek(int seconds) {
    return _call('media', {'a': 'seek', 'v': '$seconds'});
  }

  Future<void> volume(int direction) => _call('vol', {'d': '$direction'});

  Future<void> toggleDesktopMode() => _call('ua');

  Future<void> _call(String cmd, [Map<String, String?> query = const {}]) {
    return _client.getJson('/api/$cmd', query);
  }
}
