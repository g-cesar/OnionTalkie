import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/theme/app_theme.dart';
import '../providers/tor_provider.dart';

class OnionAddressScreen extends ConsumerWidget {
  const OnionAddressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final torStatus = ref.watch(torProvider);
    final theme = Theme.of(context);
    final address = torStatus.onionAddress ?? 'Non disponibile';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Il mio indirizzo'),
      ),
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
                    data: torStatus.onionAddress!,
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

              // Address text
              Text(
                'Il tuo indirizzo Onion',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.outline),
                ),
                child: SelectableText(
                  address,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),

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
                          'Alcuni scanner QR aggiungono automaticamente http:// — '
                          'il prefisso viene rimosso automaticamente quando si compone.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.yellow,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Action buttons
              if (torStatus.onionAddress != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: torStatus.onionAddress!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Indirizzo copiato negli appunti')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copia'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          if (kIsWeb) {
                            Clipboard.setData(ClipboardData(text: torStatus.onionAddress!));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Indirizzo copiato negli appunti')),
                              );
                            }
                          } else {
                            await SharePlus.instance.share(ShareParams(text: torStatus.onionAddress!));
                          }
                        },
                        icon: const Icon(Icons.share),
                        label: const Text('Condividi'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
