import 'package:couchkit_remote/core/network/tv_client.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/services/cam_service.dart';
import 'package:couchkit_remote/data/services/cast_service.dart';
import 'package:couchkit_remote/data/services/clock_service.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';
import 'package:couchkit_remote/data/services/phonebro_service.dart';

/// Cria o servico de cada app para um endpoint (token e porta ja incluidos).
class TvServiceFactory {
  const TvServiceFactory();

  PhoneBroService phonebro(TvEndpoint e) => PhoneBroService(TvClient(e));

  HubService hub(TvEndpoint e) => HubService(TvClient(e));

  CastService cast(TvEndpoint e) => CastService(TvClient(e));

  ClockService clock(TvEndpoint e) => ClockService(TvClient(e));

  CamService cam(TvEndpoint e) => CamService(TvClient(e));
}
