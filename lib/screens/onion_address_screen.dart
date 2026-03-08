import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../core/theme/app_theme.dart';
import '../providers/tor_provider.dart';
import '../providers/settings_provider.dart';

class OnionAddressScreen extends ConsumerWidget {
  const OnionAddressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final torStatus = ref.watch(torProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final address = torStatus.onionAddress ?? S.of(context).notAvailable;

    String qrData = address;
    if (torStatus.onionAddress != null && settings.availability.isNotEmpty) {
      qrData =
          'oniontalkie://${torStatus.onionAddress}?availability=${Uri.encodeComponent(settings.availability)}';
    }

    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).myAddress)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // QR Code
              if (torStatus.onionAddress != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black87,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // Address field with inline actions
              Text(
                S.of(context).yourOnionAddress,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: address,
                readOnly: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.language),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: S.of(context).copy,
                        onPressed: () {
                          if (torStatus.onionAddress != null) {
                            Clipboard.setData(
                              ClipboardData(text: torStatus.onionAddress!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.of(context).addressCopied),
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, size: 20),
                        tooltip: S.of(context).share,
                        onPressed: () async {
                          if (torStatus.onionAddress != null) {
                            if (kIsWeb) {
                              Clipboard.setData(
                                ClipboardData(text: torStatus.onionAddress!),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(S.of(context).addressCopied),
                                  ),
                                );
                              }
                            } else {
                              await SharePlus.instance.share(
                                ShareParams(text: torStatus.onionAddress!),
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 24),

              // Availability section with inline actions
              Text(
                S.of(context).availability,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: settings.availability,
                decoration: InputDecoration(
                  hintText: S.of(context).availabilityHint,
                  prefixIcon: const Icon(Icons.event_available),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: S.of(context).copyAvailability,
                        onPressed: () {
                          if (settings.availability.isNotEmpty) {
                            Clipboard.setData(
                              ClipboardData(text: settings.availability),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.of(context).availabilityCopied),
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, size: 20),
                        tooltip: S.of(context).shareAvailability,
                        onPressed: () async {
                          if (settings.availability.isNotEmpty) {
                            if (kIsWeb) {
                              Clipboard.setData(
                                ClipboardData(text: settings.availability),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      S.of(context).availabilityCopied,
                                    ),
                                  ),
                                );
                              }
                            } else {
                              await SharePlus.instance.share(
                                ShareParams(text: settings.availability),
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                style: theme.textTheme.bodyMedium,
                onChanged:
                    (val) => ref
                        .read(settingsProvider.notifier)
                        .setAvailability(val.trim()),
              ),
              const SizedBox(height: 16),

              // Warning about QR scanners
              if (torStatus.onionAddress != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.yellow.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.yellow,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          S.of(context).qrScannerNote,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.yellow,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
