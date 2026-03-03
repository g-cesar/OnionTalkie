import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/settings_provider.dart';

class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sicurezza'),
      ),
      body: ListView(
        children: [
          // Cipher Selection
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Cifra di crittografia',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Seleziona l\'algoritmo di cifratura. Entrambe le parti vedranno '
              'un indicatore verde (match) o rosso (mismatch) durante la chiamata.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),

          ...availableCiphers.map((cipher) {
            final isSelected = cipher.name == settings.cipher;
            return Column(
              children: [
                RadioListTile<String>(
                  title: Text(cipher.displayName),
                  subtitle: Text('${cipher.keyBits}-bit • ${cipher.family}'),
                  value: cipher.name,
                  groupValue: settings.cipher,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(settingsProvider.notifier).setCipher(value);
                    }
                  },
                  secondary: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cipher.keyBits >= 256
                          ? AppColors.mint.withValues(alpha: 0.1)
                          : cipher.keyBits >= 192
                              ? AppColors.yellow.withValues(alpha: 0.1)
                              : AppColors.coral.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${cipher.keyBits}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cipher.keyBits >= 256
                            ? AppColors.mint
                            : cipher.keyBits >= 192
                                ? AppColors.yellow
                                : AppColors.coral,
                      ),
                    ),
                  ),
                ),
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            cipher.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }),

          const Divider(height: 32),

          // HMAC Authentication
          SwitchListTile(
            secondary: const Icon(Icons.verified_user),
            title: const Text('Autenticazione HMAC'),
            subtitle: const Text(
              'Firma tutti i messaggi con HMAC-SHA256. '
              'Entrambe le parti devono abilitarlo.',
            ),
            value: settings.hmacEnabled,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setHmacEnabled(value);
            },
          ),

          if (settings.hmacEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.yellow.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.yellow, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'L\'HMAC viene congelato all\'inizio della chiamata. '
                        'Le modifiche avranno effetto nella chiamata successiva. '
                        'Non compatibile con versioni precedenti alla 1.1.3.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const Divider(height: 32),

          // Secret passphrase protection
          SwitchListTile(
            secondary: const Icon(Icons.enhanced_encryption),
            title: const Text('Passphrase protezione segreto'),
            subtitle: const Text(
              'Cifra il segreto condiviso a riposo con '
              'AES-256-CBC e 100.000 iterazioni PBKDF2',
            ),
            value: settings.secretPassphraseEnabled,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setSecretPassphraseEnabled(value);
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
