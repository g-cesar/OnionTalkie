import 'package:flutter/material.dart';

/// Compact action card with icon on the left and text to the right,
/// centred vertically.  Used for secondary actions (Contacts, Address).
class MenuActionCardCompact extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color textColor;
  final Color backgroundColor;
  final VoidCallback? onTap;

  const MenuActionCardCompact({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.textColor,
    required this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = onTap == null;
    final bg = isDisabled ? theme.colorScheme.surfaceContainer : backgroundColor;
    final fg = isDisabled ? theme.colorScheme.onSurfaceVariant : textColor;
    final ic = isDisabled ? theme.colorScheme.onSurfaceVariant : iconColor;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isDisabled ? 0.4 : 1.0,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: ic.withValues(alpha: 0.12),
          highlightColor: ic.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // ── Icon ──
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: ic.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: ic, size: 22),
                ),
                const SizedBox(width: 14),
                // ── Text ──
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // ── Chevron ──
                Icon(
                  Icons.chevron_right,
                  color: ic.withValues(alpha: 0.4),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
