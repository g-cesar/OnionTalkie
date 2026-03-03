import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
        title: Text(S.of(context).securityTitle),
      ),
      body: ListView(
        children: [
          // Cipher Selection
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              S.of(context).cipherSelection,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              S.of(context).cipherSelectionHint,
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
                            localizedCipherDescription(cipher.name, S.of(context)),
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
            title: Text(S.of(context).hmacAuth),
            subtitle: Text(
              S.of(context).hmacAuthSubtitle,
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
                        S.of(context).hmacFreezeNote,
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
            title: Text(S.of(context).passphraseProtection),
            subtitle: Text(
              S.of(context).passphraseProtectionSubtitle,
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
