// Tor service — platform-adaptive barrel.
//
// On native uses a local Tor process.
// On web connects to a relay server via WebSocket.
export 'tor_service_base.dart';

import 'tor_service_stub.dart'
    if (dart.library.io) 'tor_service_native.dart'
    if (dart.library.html) 'tor_service_web.dart' as impl;

import 'tor_service_base.dart';

/// Create a platform-appropriate TorService.
TorServiceBase createTorService() => impl.createTorService();
