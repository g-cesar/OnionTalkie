import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../screens/call_screen.dart';
import '../../screens/contact_edit_screen.dart';
import '../../screens/contacts_screen.dart';
import '../../screens/dial_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/onion_address_screen.dart';
import '../../screens/qr_scanner_screen.dart';
import '../../screens/settings/audio_settings_screen.dart';
import '../../screens/settings/security_settings_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/settings/tor_settings_screen.dart';
import '../../screens/settings/voice_changer_screen.dart';
import '../../screens/shared_secret_screen.dart';
import '../../screens/status_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'call',
            builder: (context, state) {
              // Accept String (legacy) or Map with address + contactId.
              final extra = state.extra;
              String? address;
              String? contactId;
              if (extra is String) {
                address = extra;
              } else if (extra is Map) {
                address = extra['address'] as String?;
                contactId = extra['contactId'] as String?;
              }
              return CallScreen(
                remoteAddress: address,
                contactId: contactId,
              );
            },
          ),
          GoRoute(
            path: 'dial',
            builder: (context, state) => const DialScreen(),
          ),
          GoRoute(
            path: 'onion-address',
            builder: (context, state) => const OnionAddressScreen(),
          ),
          GoRoute(
            path: 'shared-secret',
            builder: (context, state) => const SharedSecretScreen(),
          ),
          GoRoute(
            path: 'status',
            builder: (context, state) => const StatusScreen(),
          ),
          GoRoute(
            path: 'qr-scanner',
            builder: (context, state) => const QrScannerScreen(),
          ),
          GoRoute(
            path: 'contacts',
            builder: (context, state) => const ContactsScreen(),
            routes: [
              GoRoute(
                path: 'add',
                builder: (context, state) => const ContactEditScreen(),
              ),
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final contactId = state.extra as String?;
                  return ContactEditScreen(contactId: contactId);
                },
              ),
            ],
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'security',
                builder: (context, state) => const SecuritySettingsScreen(),
              ),
              GoRoute(
                path: 'audio',
                builder: (context, state) => const AudioSettingsScreen(),
              ),
              GoRoute(
                path: 'tor',
                builder: (context, state) => const TorSettingsScreen(),
              ),
              GoRoute(
                path: 'voice-changer',
                builder: (context, state) => const VoiceChangerScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          'Page not found: ${state.error}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    ),
  );
});
