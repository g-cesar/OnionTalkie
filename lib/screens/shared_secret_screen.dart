import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/app_settings.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import '../services/encryption_service.dart';

class SharedSecretScreen extends ConsumerStatefulWidget {
  const SharedSecretScreen({super.key});

  @override
  ConsumerState<SharedSecretScreen> createState() => _SharedSecretScreenState();
}

class _SharedSecretScreenState extends ConsumerState<SharedSecretScreen> {
  final _secretController = TextEditingController();
  final _passphraseController = TextEditingController();
  bool _obscureSecret = true;
  bool _obscurePassphrase = true;
  bool _usePassphrase = false;
  bool _hasExistingSecret = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final storage = ref.read(storageServiceProvider);
    final hasSecret = await storage.hasSharedSecret();
    setState(() {
      _hasExistingSecret = hasSecret;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _secretController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _saveSecret() async {
    final secret = _secretController.text.trim();
    if (secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un segreto condiviso')),
      );
      return;
    }

    final storage = ref.read(storageServiceProvider);
    final encryption = ref.read(encryptionServiceProvider);

    if (_usePassphrase && _passphraseController.text.isNotEmpty) {
      // Encrypt the secret with passphrase
      final encrypted = EncryptionService.encryptSecretWithPassphrase(
        secret,
        _passphraseController.text,
      );
      await storage.saveSharedSecret('ENCRYPTED:$encrypted');
    } else {
      await storage.saveSharedSecret(secret);
    }

    encryption.setSharedSecret(secret);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Segreto condiviso salvato')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _deleteSecret() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina segreto'),
        content: const Text(
          'Sei sicuro di voler eliminare il segreto condiviso? '
          'Non potrai effettuare chiamate cifrate senza un segreto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final storage = ref.read(storageServiceProvider);
      await storage.deleteSharedSecret();
      ref.read(encryptionServiceProvider).setSharedSecret('');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Segreto eliminato')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Segreto Condiviso'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info card
            _buildInfoCard(context, theme),

            const SizedBox(height: 24),

            // Status
            if (_hasExistingSecret) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.mint.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.mint.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Un segreto condiviso è già configurato'),
                    ),
                    TextButton(
                      onPressed: _deleteSecret,
                      child: Text(
                        'Elimina',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Secret input
            Text(
              _hasExistingSecret ? 'Aggiorna segreto' : 'Nuovo segreto',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secretController,
              obscureText: _obscureSecret,
              decoration: InputDecoration(
                labelText: 'Segreto condiviso',
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureSecret ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Passphrase option
            SwitchListTile(
              title: const Text('Proteggi con passphrase'),
              subtitle: const Text(
                'Cifra il segreto a riposo con AES-256-CBC',
              ),
              value: _usePassphrase,
              onChanged: (value) => setState(() => _usePassphrase = value),
            ),

            if (_usePassphrase) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _passphraseController,
                obscureText: _obscurePassphrase,
                decoration: InputDecoration(
                  labelText: 'Passphrase',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassphrase
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassphrase = !_obscurePassphrase),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            FilledButton.icon(
              onPressed: _saveSecret,
              icon: const Icon(Icons.save),
              label: const Text('Salva segreto'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Info card (adapts to key exchange mode) ─────────────────────

  Widget _buildInfoCard(BuildContext context, ThemeData theme) {
    final settings = ref.watch(settingsProvider);
    final isPake = settings.keyExchangeMode == KeyExchangeMode.pake;

    final color = isPake ? AppColors.mint : AppColors.yellow;
    final icon = isPake ? Icons.handshake : Icons.info_outline;
    final text = isPake
        ? 'Modalità PAKE (SPAKE2) attiva. La passphrase NON viene mai trasmessa — '
          'viene usata per derivare una chiave di sessione unica ad ogni chiamata '
          'tramite scambio zero-knowledge.'
        : 'Entrambe le parti devono usare lo stesso segreto condiviso. '
          'Scambiate il segreto tramite un canale sicuro (di persona, '
          'messaggistica cifrata, ecc.).';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isPake) ...[
                  Text(
                    'SPAKE2 — Zero-Knowledge',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
