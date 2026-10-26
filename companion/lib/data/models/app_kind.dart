import 'package:flutter/material.dart';

/// Apps da TV que o companion sabe controlar.
enum AppKind {
  firehome(
    label: 'FireHome',
    description: 'Launcher personalizável',
    pageTitle: 'FireHome',
    icon: Icons.home_filled,
    color: Color(0xFFEB5757),
    portStart: 9000,
    portEnd: 9040,
  ),
  phonebro(
    label: 'PhoneBro',
    description: 'Navegador da TV',
    pageTitle: 'PhoneBro',
    icon: Icons.language,
    color: Color(0xFF2F80ED),
    portStart: 8765,
    portEnd: 8805,
  ),
  stickhub(
    label: 'StickHub',
    description: 'Apps e sistema',
    pageTitle: 'StickHub',
    icon: Icons.apps,
    color: Color(0xFF27AE60),
    portStart: 8800,
    portEnd: 8840,
  ),
  phonecast(
    label: 'PhoneCast',
    description: 'Enviar mídia para a TV',
    pageTitle: 'PhoneCast',
    icon: Icons.cast,
    color: Color(0xFF9B51E0),
    portStart: 8850,
    portEnd: 8890,
  ),
  stickclock(
    label: 'StickClock',
    description: 'Relógio, clima e lista',
    pageTitle: 'StickClock',
    icon: Icons.access_time_filled,
    color: Color(0xFF56CCF2),
    portStart: 8900,
    portEnd: 8940,
  ),
  homecam(
    label: 'HomeCam',
    description: 'Câmeras (go2rtc)',
    pageTitle: 'HomeCam',
    icon: Icons.videocam,
    color: Color(0xFFF2994A),
    portStart: 8950,
    portEnd: 8990,
  );

  const AppKind({
    required this.label,
    required this.description,
    required this.pageTitle,
    required this.icon,
    required this.color,
    required this.portStart,
    required this.portEnd,
  });

  final String label;
  final String description;

  /// Texto do <title> da pagina web do app (usado para identifica-lo).
  final String pageTitle;
  final IconData icon;
  final Color color;
  final int portStart;
  final int portEnd;

  static AppKind? fromHtml(String html) {
    final match = RegExp(
      r'<title>([^<]*)',
      caseSensitive: false,
    ).firstMatch(html);
    final title = match?.group(1)?.trim() ?? '';
    for (final kind in AppKind.values) {
      if (title.startsWith(kind.pageTitle)) {
        return kind;
      }
    }
    return null;
  }

  static AppKind? byName(String name) {
    for (final kind in AppKind.values) {
      if (kind.name == name) {
        return kind;
      }
    }
    return null;
  }
}
