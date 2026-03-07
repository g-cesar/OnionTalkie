import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../models/contact.dart';
import '../providers/contacts_provider.dart';
import '../providers/online_status_provider.dart';
import '../providers/tor_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Screen showing the address book.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    final torStatus = ref.watch(torProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).contactsTitle),
        actions: [
          if (contacts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: S.of(context).refreshStatus,
              onPressed: () {
                for (final contact in contacts) {
                  ref.invalidate(onlineStatusProvider(contact.onionAddress));
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(S.of(context).refreshingStatus),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          for (final contact in contacts) {
            ref.invalidate(onlineStatusProvider(contact.onionAddress));
          }
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child:
            contacts.isEmpty
                ? SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height - 100,
                    child: _buildEmptyState(context),
                  ),
                )
                : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: contacts.length,
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    return _ContactTile(
                      contact: contact,
                      torReady: torStatus.isReady,
                      onCall:
                          torStatus.isReady
                              ? () => _callContact(context, ref, contact)
                              : null,
                      onTap:
                          () =>
                              context.push('/contacts/edit', extra: contact.id),
                    );
                  },
                ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/contacts/add'),
        backgroundColor: AppColors.yellow,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.contacts_outlined,
              size: 80,
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              S.of(context).noContacts,
              style: theme.textTheme.titleLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context).addContactHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _callContact(BuildContext context, WidgetRef ref, Contact contact) {
    context.push(
      '/call',
      extra: {'address': contact.onionAddress, 'contactId': contact.id},
    );
  }
}

// ── Contact list tile ──────────────────────────────────────────────

class _ContactTile extends ConsumerWidget {
  final Contact contact;
  final bool torReady;
  final VoidCallback? onCall;
  final VoidCallback? onTap;

  const _ContactTile({
    required this.contact,
    required this.torReady,
    this.onCall,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Only probe online status when Tor is ready
    final onlineAsync =
        torReady ? ref.watch(onlineStatusProvider(contact.onionAddress)) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar with online dot
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _buildAvatar(cs),
                    if (torReady)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: _OnlineDot(asyncValue: onlineAsync),
                      ),
                  ],
                ),
                const SizedBox(width: 14),

                // Name + onion
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              contact.alias,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (contact.addressChanged)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Tooltip(
                                message: S.of(context).onionAddressChanged,
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 18,
                                  color: AppColors.coral,
                                ),
                              ),
                            ),
                          if (!contact.hasSecret)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Tooltip(
                                message: S.of(context).noSharedSecret,
                                child: Icon(
                                  Icons.key_off,
                                  size: 16,
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        contact.shortOnion,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (contact.lastContactedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            S
                                .of(context)
                                .lastContact(
                                  _formatDate(
                                    context,
                                    contact.lastContactedAt!,
                                  ),
                                ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Call button
                IconButton(
                  onPressed: onCall,
                  icon: Icon(Icons.call, color: AppColors.mint),
                  tooltip: S.of(context).callTooltip,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.mint.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(ColorScheme cs) {
    final initials =
        contact.alias.isNotEmpty ? contact.alias[0].toUpperCase() : '?';
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.yellow,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }

  String _formatDate(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return S.of(context).timeNow;
    if (diff.inHours < 1) return S.of(context).timeMinAgo(diff.inMinutes);
    if (diff.inDays < 1) return S.of(context).timeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return S.of(context).timeDaysAgo(diff.inDays);
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ── Online status dot ──────────────────────────────────────────────

/// Small coloured dot that indicates whether a peer is online.
/// - Loading → small grey spinner
/// - Online  → green dot
/// - Offline → grey dot
class _OnlineDot extends StatelessWidget {
  final AsyncValue<bool>? asyncValue;
  const _OnlineDot({this.asyncValue});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: _dot(),
    );
  }

  Widget _dot() {
    if (asyncValue == null) return const SizedBox.shrink();

    return asyncValue!.when(
      skipLoadingOnRefresh: false,
      data:
          (isOnline) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? AppColors.mint : Colors.grey.shade500,
              shape: BoxShape.circle,
            ),
          ),
      loading:
          () => const SizedBox(
            width: 8,
            height: 8,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
      error:
          (_, __) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey.shade500,
              shape: BoxShape.circle,
            ),
          ),
    );
  }
}
