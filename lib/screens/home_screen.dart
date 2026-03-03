import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../models/tor_status.dart';
import '../providers/circuit_provider.dart';
import '../providers/contacts_provider.dart';
import '../providers/tor_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/circuit_path_widget.dart';
import '../widgets/menu_action_card.dart';
import '../widgets/menu_action_card_compact.dart';
import '../widgets/status_card.dart';
import 'tor_install_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTorInstalled();
    });
  }

  Future<void> _checkTorInstalled() async {
    await ref.read(torProvider.notifier).checkTorInstalled();
  }

  @override
  Widget build(BuildContext context) {
    final torStatus = ref.watch(torProvider);
    final settings = ref.watch(settingsProvider);
    final circuitHops = ref.watch(circuitHopsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 16),

            // ── Header row ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.of(context).appTitle,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        S.of(context).appSubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _HeaderIconButton(
                  icon: Icons.assessment_outlined,
                  onTap: () => context.push('/status'),
                ),
                const SizedBox(width: 8),
                _HeaderIconButton(
                  icon: Icons.settings_outlined,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Status Banner ──
            StatusCard(torStatus: torStatus),

            // ── Circuit Path (when Tor connected + enabled) ──
            if (torStatus.state == TorConnectionState.connected &&
                settings.showCircuitPath &&
                circuitHops != null)
              CircuitPathWidget(hops: circuitHops),

            const SizedBox(height: 28),

            // ── Section label ──
            _SectionLabel(label: S.of(context).quickActions),

            const SizedBox(height: 14),

            // ── Bento Grid ──
            Column(
              children: [
                // ── Primary row: Ascolta + Chiama ──
                SizedBox(
                  height: 160,
                  child: Row(
                    children: [
                      Expanded(
                        child: MenuActionCard(
                          icon: Icons.hearing,
                          title: S.of(context).listen,
                          subtitle: S.of(context).listenSubtitle,
                          color: AppColors.yellow,
                          onTap: torStatus.isReady
                              ? () => context.push('/call')
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MenuActionCard(
                          icon: Icons.call,
                          title: S.of(context).call,
                          subtitle: S.of(context).callSubtitle,
                          color: AppColors.mint,
                          onTap: torStatus.isReady
                              ? () => context.push('/dial')
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // ── Secondary row: Contatti + Indirizzo (compact) ──
                SizedBox(
                  height: 72,
                  child: Row(
                    children: [
                      Expanded(
                        child: _ContactsCompactCard(
                          onTap: () => context.push('/contacts'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MenuActionCardCompact(
                          icon: Icons.qr_code,
                          title: S.of(context).address,
                          subtitle: S.of(context).addressSubtitle,
                          iconColor: AppColors.yellow,
                          textColor: AppColors.yellow,
                          backgroundColor: Colors.white,
                          onTap: torStatus.isReady
                              ? () => context.push('/onion-address')
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Section label ──
            Row(
              children: [
                Expanded(child: _SectionLabel(label: S.of(context).torAndSystem)),
                if (torStatus.isReady)
                  TextButton.icon(
                    onPressed: () => context.push('/status'),
                    icon: Icon(Icons.north_east, size: 16, color: cs.primary),
                    label: Text(
                      S.of(context).status,
                      style: TextStyle(color: cs.primary),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // ── List tiles ──
            _buildTorActionTile(context, torStatus),
            _buildListTile(
              context,
              icon: Icons.assessment,
              title: S.of(context).systemStatus,
              subtitle: S.of(context).systemStatusSubtitle,
              onTap: () => context.push('/status'),
            ),
            if (torStatus.isReady)
              _buildListTile(
                context,
                icon: Icons.refresh,
                title: S.of(context).rotateOnion,
                subtitle: S.of(context).rotateOnionSubtitle,
                onTap: () => _showRotateConfirmation(context),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── Tor action tile ──────────────────────────────────────────────

  Widget _buildTorActionTile(BuildContext context, TorStatus torStatus) {
    switch (torStatus.state) {
      case TorConnectionState.notInstalled:
        return _buildListTile(
          context,
          icon: Icons.download,
          title: S.of(context).installTor,
          subtitle: S.of(context).installTorSubtitle,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TorInstallScreen()),
          ),
        );
      case TorConnectionState.stopped:
      case TorConnectionState.error:
        return _buildListTile(
          context,
          icon: Icons.play_arrow,
          title: S.of(context).startTor,
          subtitle: torStatus.errorMessage ?? S.of(context).startTorSubtitle,
          onTap: () {
            final settings = ref.read(settingsProvider);
            ref.read(torProvider.notifier).start(
              snowflake: settings.snowflakeEnabled,
              excludeNodes: settings.excludeNodes,
            );
          },
        );
      case TorConnectionState.starting:
      case TorConnectionState.bootstrapping:
        return _buildListTile(
          context,
          icon: Icons.hourglass_top,
          title: S.of(context).torStarting,
          subtitle: S.of(context).torBootstrapProgress(torStatus.bootstrapProgress),
          trailing: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              value: torStatus.bootstrapProgress / 100,
              strokeWidth: 2,
            ),
          ),
        );
      case TorConnectionState.connected:
        return _buildListTile(
          context,
          icon: Icons.stop,
          title: S.of(context).stopTor,
          subtitle: S.of(context).stopTorSubtitle,
          onTap: () => ref.read(torProvider.notifier).stop(),
        );
    }
  }

  // ─── List tile ────────────────────────────────────────────────────

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          trailing: trailing ??
              (onTap != null
                  ? Icon(Icons.chevron_right, color: cs.onSurfaceVariant)
                  : null),
          onTap: onTap,
        ),
      ),
    );
  }

  // ─── Rotate confirmation ──────────────────────────────────────────

  void _showRotateConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).rotateOnionTitle),
        content: Text(S.of(context).rotateOnionConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.of(context).cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(torProvider.notifier).rotateOnionAddress();
            },
            child: Text(S.of(context).rotate),
          ),
        ],
      ),
    );
  }
}

// ─── Small helper widgets ─────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: cs.primary, size: 22),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
    );
  }
}

/// Compact action card that shows the contacts count badge.
class _ContactsCompactCard extends ConsumerWidget {
  final VoidCallback? onTap;
  const _ContactsCompactCard({this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    final count = contacts.length;
    final subtitle = S.of(context).contactCount(count);

    return MenuActionCardCompact(
      icon: Icons.contacts,
      title: S.of(context).contacts,
      subtitle: subtitle,
      iconColor: const Color(0xFF3A7BD5),
      textColor: const Color(0xFF3A7BD5),
      backgroundColor: Colors.white,
      onTap: onTap,
    );
  }
}
