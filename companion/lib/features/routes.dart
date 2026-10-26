import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/di/injector.dart';
import 'package:couchkit_remote/core/navigation/router.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/tv_service_factory.dart';
import 'package:couchkit_remote/features/add/add_page.dart';
import 'package:couchkit_remote/features/cam/cam_page.dart';
import 'package:couchkit_remote/features/cast/cast_page.dart';
import 'package:couchkit_remote/features/clock/clock_page.dart';
import 'package:couchkit_remote/features/firehome/firehome_page.dart';
import 'package:couchkit_remote/features/home/home_page.dart';
import 'package:couchkit_remote/features/hub/hub_page.dart';
import 'package:couchkit_remote/features/phonebro/phonebro_page.dart';

class AppRoutes implements RouteModule {
  AppRoutes(this._injector);

  final Injector _injector;

  TvServiceFactory get _services => _injector.get<TvServiceFactory>();

  @override
  void register(RouterService router) {
    router.register(HomePage.route, (context, args) => const HomePage());
    router.register(AddPage.route, (context, args) => const AddPage());
    router.register(
      FireHomePage.route,
      (context, args) => _endpointPage(args, (e) {
        return FireHomePage(service: _services.firehome(e));
      }),
    );
    router.register(
      PhoneBroPage.route,
      (context, args) => _endpointPage(args, (e) {
        return PhoneBroPage(service: _services.phonebro(e), endpoint: e);
      }),
    );
    router.register(
      HubPage.route,
      (context, args) => _endpointPage(args, (e) {
        return HubPage(service: _services.hub(e));
      }),
    );
    router.register(
      CastPage.route,
      (context, args) => _endpointPage(args, (e) {
        return CastPage(service: _services.cast(e));
      }),
    );
    router.register(
      ClockPage.route,
      (context, args) => _endpointPage(args, (e) {
        return ClockPage(service: _services.clock(e));
      }),
    );
    router.register(
      CamPage.route,
      (context, args) => _endpointPage(args, (e) {
        return CamPage(service: _services.cam(e));
      }),
    );
  }

  Widget _endpointPage(Object? args, Widget Function(TvEndpoint) build) {
    if (args is! TvEndpoint) {
      return const Scaffold(body: Center(child: Text('Endpoint ausente')));
    }
    return build(args);
  }
}
