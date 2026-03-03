import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../core/theme/app_theme.dart';
import '../services/circuit_service.dart';

/// A visually rich card showing the Tor circuit hops with country flags,
/// relay names, roles and connecting arrows.
class CircuitPathWidget extends StatelessWidget {
  final List<CircuitHop> hops;

  const CircuitPathWidget({super.key, required this.hops});

  @override
  Widget build(BuildContext context) {
    if (hops.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.yellow.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Icon(
                Icons.route_rounded,
                size: 14,
                color: AppColors.yellow.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Text(
                S.of(context).torCircuit,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.yellow,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
              ),
              const Spacer(),
              Icon(
                Icons.shield_outlined,
                size: 13,
                color: AppColors.mint.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                '${hops.length} hop',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Hops row
          SizedBox(
            height: 80,
            child: Row(
              children: [
                for (int i = 0; i < hops.length; i++) ...[
                  Expanded(child: _HopCard(hop: hops[i])),
                  if (i < hops.length - 1) _Arrow(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single hop card: flag, name, role, country.
class _HopCard extends StatelessWidget {
  final CircuitHop hop;
  const _HopCard({required this.hop});

  Color get _roleColor {
    switch (hop.role) {
      case 'Guard':
        return AppColors.mint;
      case 'Relay':
        return AppColors.yellow;
      default: // Exit / Rendezvous
        return AppColors.coral;
    }
  }

  IconData get _roleIcon {
    switch (hop.role) {
      case 'Guard':
        return Icons.shield_rounded;
      case 'Relay':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.exit_to_app_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _roleColor;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Flag
          Text(
            hop.flag,
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(height: 2),
          // Country name (or relay name as fallback)
          Text(
            hop.countryCode != null
                ? CircuitService.getLocalizedCountryName(hop.countryCode!, S.of(context))
                : hop.name,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          // Role chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_roleIcon, size: 9, color: color),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    hop.role.split('/').first, // "Exit" not "Exit/Rendezvous"
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// Animated arrow connector between hops.
class _Arrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}
