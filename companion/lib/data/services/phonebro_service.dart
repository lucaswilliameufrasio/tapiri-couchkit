import 'package:couchkit_remote/core/network/tv_client.dart';

class Bookmark {
  const Bookmark(this.title, this.url);

  final String title;
  final String url;
}

class BrowserState {
  const BrowserState({
    required this.url,
    required this.title,
    this.bookmarks = const [],
  });

  final String url;
  final String title;
  final List<Bookmark> bookmarks;
}

class PhoneBroService {
  PhoneBroService(this._client);

  final TvClient _client;

  Future<BrowserState> state() async {
    final json = await _client.getJson('/api/state');
    final marks = <Bookmark>[];
    for (final line in '${json['bookmarks'] ?? ''}'.split('\n')) {
      final parts = line.split('\t');
      if (parts.length >= 2 && parts[1].isNotEmpty) {
        marks.add(Bookmark(parts[0], parts[1]));
      }
    }
    return BrowserState(
      url: '${json['url'] ?? ''}',
      title: '${json['title'] ?? ''}',
      bookmarks: marks,
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

  Future<void> zoom(double factor) => _call('zoom', {'f': '$factor'});

  /// Favorita a pagina aberta na TV.
  Future<void> addBookmark() => _call('fav');

  Future<void> removeBookmark(String url) => _call('unfav', {'url': url});

  Future<void> toggleDesktopMode() => _call('ua');

  Future<void> _call(String cmd, [Map<String, String?> query = const {}]) {
    return _client.getJson('/api/$cmd', query);
  }
}
