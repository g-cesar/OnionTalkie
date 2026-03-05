import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/settings_provider.dart';

class OnionTalkieApp extends ConsumerWidget {
  const OnionTalkieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final theme = AppTheme.darkTheme();
    final settings = ref.watch(settingsProvider);

    // Determine locale: empty string → follow device, otherwise explicit
    final Locale? overrideLocale =
        settings.locale.isEmpty ? null : Locale(settings.locale);

    // Force dark status / navigation bars
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.darkBg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return WithForegroundTask(
      child: MaterialApp.router(
        title: 'OnionTalkie',
        debugShowCheckedModeBanner: false,
        theme: theme,
        darkTheme: theme,
        themeMode: ThemeMode.dark,
        routerConfig: router,
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: overrideLocale,
        localeResolutionCallback: (locale, supportedLocales) {
          if (locale != null) {
            for (var supportedLocale in supportedLocales) {
              if (supportedLocale.languageCode == locale.languageCode) {
                return supportedLocale;
              }
            }
          }
          // Default fallback to English
          return const Locale('en', '');
        },
      ),
    );
  }
}
