/// Um ajuste da TV: lista de comandos de shell e a lista para desfazer.
class TuneProfile {
  const TuneProfile({
    required this.id,
    required this.title,
    required this.description,
    required this.apply,
    this.undo = const [],
  });

  final String id;
  final String title;
  final String description;
  final List<String> apply;
  final List<String> undo;

  bool get undoable => undo.isNotEmpty;
}

/// Apps da Amazon de anuncios, metricas e servicos que quase ninguem usa.
const debloatPackages = [
  'com.amazon.shoptv.client',
  'com.amazon.shoptv.firetv.client',
  'com.amazon.minitv.android.app',
  'com.amazon.imdb.tv.android.app',
  'com.imdb.livingroom.firetv',
  'com.amazon.naatyam',
  'com.amazon.bueller.music',
  'com.amazon.bueller.photos',
  'com.amazon.bueller.notification',
  'com.amazon.gamehub',
  'com.amazon.recess',
  'com.amazon.tv.livetv',
  'com.amazon.tv.releasenotes',
  'com.amazon.perfcollection',
  'com.amazon.logan',
  'com.amazon.dp.logger',
  'com.amazon.device.logmanager',
  'com.amazon.tv.fw.metrics',
  'com.amazon.wirelessmetrics.service',
  'com.amazon.device.crashmanager',
  'com.amazon.connectivitydiag',
];

List<String> _animations(String scale) => [
  'settings put global window_animation_scale $scale',
  'settings put global transition_animation_scale $scale',
  'settings put global animator_duration_scale $scale',
];

/// Valores de `settings put secure`: [privado] limita rastreio e metricas.
List<String> _privacy({required bool privado}) {
  final on = privado ? 1 : 0;
  final off = privado ? 0 : 1;
  return [
    'settings put secure limit_ad_tracking $on',
    'settings put secure non_amz_limit_ad_tracking $on',
    'settings put secure amz_limit_ad_tracking $on',
    'settings put secure advertisingIdApp:interestBasedAds:value $off',
    'settings put secure USAGE_METRICS_UPLOAD_ENABLED $off',
    'settings put secure usage_metrics_marketing_enabled $off',
    'settings put secure settingsApp:appUsageData:value $off',
    'settings put secure settingsApp:deviceUsageData:value $off',
    'settings put secure screensaver_enabled $off',
  ];
}

final tuneProfiles = [
  TuneProfile(
    id: 'animacoes',
    title: 'Animações rápidas',
    description: 'Transições do sistema em 0,5x: a TV parece mais ágil.',
    apply: _animations('0.5'),
    undo: _animations('1'),
  ),
  TuneProfile(
    id: 'debloat',
    title: 'Menos lixo da Amazon',
    description:
        'Desativa ${debloatPackages.length} apps de anúncios, métricas e '
        'serviços que você não usa. Dá para desfazer.',
    apply: [for (final pkg in debloatPackages) 'pm disable-user --user 0 $pkg'],
    undo: [for (final pkg in debloatPackages) 'pm enable $pkg'],
  ),
  TuneProfile(
    id: 'privacidade',
    title: 'Privacidade',
    description: 'Limita anúncios personalizados e o envio de dados de uso.',
    apply: _privacy(privado: true),
    undo: _privacy(privado: false),
  ),
  const TuneProfile(
    id: 'compilar',
    title: 'Limpar cache e compilar',
    description:
        'Esvazia caches e recompila o launcher e as configurações da Amazon '
        'para abrirem mais rápido. Pode levar um minuto.',
    apply: [
      'pm trim-caches 999G',
      'cmd package compile -m speed -f com.amazon.tv.launcher',
      'cmd package compile -m speed -f com.amazon.tv.settings.v2',
    ],
  ),
];
