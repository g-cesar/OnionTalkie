import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/contact.dart';
import '../providers/contacts_provider.dart';
import '../providers/providers.dart';

class DialScreen extends ConsumerStatefulWidget {
  const DialScreen({super.key});

  @override
  ConsumerState<DialScreen> createState() => _DialScreenState();
}

class _DialScreenState extends ConsumerState<DialScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _sanitizeAddress(String input) {
    // Strip http:// or https:// prefix (some QR scanners add it)
    return input
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/$'), '')
        .trim();
  }

  void _call() {
    if (_formKey.currentState?.validate() ?? false) {
      final address = _sanitizeAddress(_controller.text);
      // Check if this address matches a contact
      final contact =
          ref.read(contactsProvider.notifier).findByOnion(address);
      if (contact != null) {
        // Known contact — secret is loaded in CallScreen via contactId
        context.push('/call', extra: {
          'address': address,
          'contactId': contact.id,
        });
      } else {
        // Unknown address — prompt for a one-time secret
        _showAdHocSecretDialog(address);
      }
    }
  }

  /// Show a dialog to optionally enter a one-time shared secret
  /// for an address not saved in contacts.
  void _showAdHocSecretDialog(String address) {
    final secretCtrl = TextEditingController();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Segreto condiviso'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Questo indirizzo non è in rubrica.\n'
                'Inserisci il segreto condiviso con questa persona '
                '(oppure lascia vuoto per non cifrare).',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: secretCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Segreto (opzionale)',
                  prefixIcon: const Icon(Icons.key, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                      size: 20,
                    ),
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                final secret = secretCtrl.text.trim();
                if (secret.isNotEmpty) {
                  ref
                      .read(encryptionServiceProvider)
                      .setSharedSecret(secret);
                }
                context.push('/call', extra: address);
              },
              child: const Text('Chiama'),
            ),
          ],
        ),
      ),
    );
  }

  void _callContact(Contact contact) {
    context.push('/call', extra: {
      'address': contact.onionAddress,
      'contactId': contact.id,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chiama'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.call,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Inserisci l\'indirizzo .onion\ndella persona da chiamare',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: 'Indirizzo .onion',
                  hintText: 'xxxxx.onion',
                  prefixIcon: const Icon(Icons.language),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _controller.text = _sanitizeAddress(data!.text!);
                      }
                    },
                  ),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Inserisci un indirizzo';
                  }
                  final sanitized = _sanitizeAddress(value);
                  if (!sanitized.endsWith('.onion')) {
                    return 'L\'indirizzo deve terminare con .onion';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _call(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await context.push<String>('/qr-scanner');
                      if (result != null && result.isNotEmpty && context.mounted) {
                        _controller.text = result;
                        _call();
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scansiona QR'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Quick contacts ──
            _QuickContacts(onSelectContact: _callContact),

            const Spacer(),
            FilledButton.icon(
              onPressed: _call,
              icon: const Icon(Icons.call),
              label: const Text('Chiama'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a quick-pick list of saved contacts below the manual address field.
class _QuickContacts extends ConsumerWidget {
  final void Function(Contact contact) onSelectContact;

  const _QuickContacts({required this.onSelectContact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    if (contacts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Contatti rapidi',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ...contacts.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primary.withValues(alpha: 0.15),
                    child: Text(
                      c.alias.isNotEmpty ? c.alias[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  title: Text(c.alias,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(c.shortOnion,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      )),
                  trailing: Icon(Icons.call, size: 18, color: cs.primary),
                  onTap: () => onSelectContact(c),
                ),
              ),
            )),
      ],
    );
  }
}
