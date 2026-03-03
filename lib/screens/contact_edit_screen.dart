import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../providers/contacts_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
        title: Text(S.of(context).deleteContact),
        content: Text(
          S.of(context).deleteContactConfirm(_aliasCtrl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.coral,
            ),
            child: Text(S.of(context).delete),
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
        title: Text(_isEditing ? S.of(context).editContact : S.of(context).newContact),
        actions: [
          if (_isEditing)
            IconButton(
              icon: Icon(Icons.delete_outline, color: AppColors.coral),
              tooltip: S.of(context).delete,
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
                decoration: InputDecoration(
                  labelText: S.of(context).alias,
                  hintText: S.of(context).aliasHint,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return S.of(context).aliasRequired;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Onion address ────────────────────
              TextFormField(
                controller: _onionCtrl,
                decoration: InputDecoration(
                  labelText: S.of(context).onionAddress,
                  hintText: S.of(context).onionAddressHint,
                  prefixIcon: const Icon(Icons.language),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.paste, size: 20),
                        tooltip: S.of(context).paste,
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
                        tooltip: S.of(context).scanQr,
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
                    return S.of(context).addressRequired;
                  }
                  final sanitised = _sanitiseOnion(v);
                  if (!sanitised.endsWith('.onion')) {
                    return S.of(context).addressMustEndOnion;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Shared secret ────────────────────
              TextFormField(
                controller: _secretCtrl,
                decoration: InputDecoration(
                  labelText: S.of(context).sharedSecret,
                  hintText: S.of(context).sharedSecretHint,
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
                        S.of(context).sharedSecretExplanation,
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
                label: Text(_isEditing ? S.of(context).save : S.of(context).addContactButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
