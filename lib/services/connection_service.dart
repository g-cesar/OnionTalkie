// Connection service — platform-adaptive barrel.
//
// On native uses raw TCP Socket through Tor SOCKS5.
// On web uses WebSocket through a relay server.
export 'connection_service_base.dart';

import 'connection_service_stub.dart'
    if (dart.library.io) 'connection_service_native.dart'
    if (dart.library.html) 'connection_service_web.dart' as impl;

import 'connection_service_base.dart';

/// Create a platform-appropriate ConnectionService.
ConnectionServiceBase createConnectionService() => impl.createConnectionService();
