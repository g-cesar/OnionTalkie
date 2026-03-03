// Storage service — platform-adaptive barrel.
//
// On native uses filesystem (dart:io) + SharedPreferences.
// On web uses SharedPreferences (localStorage) only.
export 'storage_service_base.dart';

import 'storage_service_stub.dart'
    if (dart.library.io) 'storage_service_native.dart'
    if (dart.library.html) 'storage_service_web.dart' as impl;

import 'storage_service_base.dart';

/// Create a platform-appropriate StorageService.
StorageServiceBase createStorageService() => impl.createStorageService();
