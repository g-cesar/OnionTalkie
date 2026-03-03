import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../providers/contacts_provider.dart';

/// Screen for adding or editing a contact.
///
/// Pass a contact id via [GoRouter.extra] to edit an existing contact,
/// or `null` to create a new one.
class ContactEditScreen extends ConsumerStatefulWidget {
  /// The id of the contact to edit. `null` means "add new".
  final String? contactId;

  const ContactEditScreen({super.key, this.contactId});

  @override
  ConsumerState<ContactEditScreen> createState() => _ContactEditScreenState();
}

class _ContactEditScreenState extends ConsumerState<ContactEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aliasCtrl = TextEditingController();
  final _onionCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  bool _showSecret = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    if (widget.contactId != null) {
      _isEditing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final contact =
            ref.read(contactsProvider.notifier).findById(widget.contactId!);
        if (contact != null) {
          _aliasCtrl.text = contact.alias;
          _onionCtrl.text = contact.onionAddress;
          _secretCtrl.text = contact.sharedSecret;
        }
      });
    }
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _onionCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  String _sanitiseOnion(String input) => input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'^https?://'), '')
      .replaceAll(RegExp(r'/$'), '');

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final alias = _aliasCtrl.text.trim();
    final onion = _sanitiseOnion(_onionCtrl.text);
    final secret = _secretCtrl.text.trim();

    if (_isEditing) {
      final existing =
          ref.read(contactsProvider.notifier).findById(widget.contactId!);
      if (existing != null) {
        await ref.read(contactsProvider.notifier).update(
              existing.copyWith(
                alias: alias,
                onionAddress: onion,
                sharedSecret: secret,
              ),
            );
      }
    } else {
      await ref.read(contactsProvider.notifier).add(
            alias: alias,
            onionAddress: onion,
            sharedSecret: secret,
          );
    }

    if (mounted) context.pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina contatto'),
        content: Text(
          'Vuoi eliminare "${_aliasCtrl.text}" dalla rubrica?\n'
          'Anche il segreto condiviso sarà rimosso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.coral,
            ),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(contactsProvider.notifier).delete(widget.contactId!);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifica contatto' : 'Nuovo contatto'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: Icon(Icons.delete_outline, color: AppColors.coral),
              tooltip: 'Elimina',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Alias ────────────────────────────
              TextFormField(
                controller: _aliasCtrl,
                decoration: const InputDecoration(
                  labelText: 'Alias',
                  hintText: 'es. Mario',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return "Inserisci un alias";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Onion address ────────────────────
              TextFormField(
                controller: _onionCtrl,
                decoration: InputDecoration(
                  labelText: 'Indirizzo .onion',
                  hintText: 'xxxxx.onion',
                  prefixIcon: const Icon(Icons.language),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.paste, size: 20),
                        tooltip: 'Incolla',
                        onPressed: () async {
                          final data =
                              await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _onionCtrl.text = _sanitiseOnion(data!.text!);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner, size: 20),
                        tooltip: 'Scansiona QR',
                        onPressed: () async {
                          final result =
                              await context.push<String>('/qr-scanner');
                          if (result != null && result.isNotEmpty) {
                            _onionCtrl.text = _sanitiseOnion(result);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return "Inserisci un indirizzo";
                  }
                  final sanitised = _sanitiseOnion(v);
                  if (!sanitised.endsWith('.onion')) {
                    return "L'indirizzo deve terminare con .onion";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Shared secret ────────────────────
              TextFormField(
                controller: _secretCtrl,
                decoration: InputDecoration(
                  labelText: 'Segreto condiviso (opzionale)',
                  hintText: 'Chiave pre-condivisa con questo contatto',
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showSecret
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _showSecret = !_showSecret),
                  ),
                ),
                obscureText: !_showSecret,
                autocorrect: false,
              ),
              const SizedBox(height: 12),

              // Help text
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: cs.onPrimaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Il segreto viene usato per cifrare la comunicazione. '
                        'Entrambi i peer devono avere lo stesso segreto. '
                        'Con SPAKE2 attivo, viene usato per derivare chiavi '
                        'di sessione uniche ad ogni chiamata.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              FilledButton.icon(
                onPressed: _save,
                icon: Icon(_isEditing ? Icons.save : Icons.person_add),
                label: Text(_isEditing ? 'Salva' : 'Aggiungi contatto'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
