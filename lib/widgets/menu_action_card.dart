import 'package:flutter/material.dart';

/// A bold action card for the home screen bento grid.
///
/// Follows the yellow/coral/mint/white design language.
class MenuActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const MenuActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = onTap == null;
    final bool isLight = _isLightColor(color);
    final Color fgColor = isLight ? const Color(0xFF0E121A) : Colors.white;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isDisabled ? 0.4 : 1.0,
      child: Material(
        color: isDisabled ? theme.colorScheme.surfaceContainer : color,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withValues(alpha: 0.15),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 140;
              final pad = compact ? 14.0 : 18.0;
              final iconSize = compact ? 32.0 : 40.0;
              final iconRadius = compact ? 10.0 : 12.0;
              final iconGlyph = compact ? 18.0 : 22.0;

              return Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon
                    Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: BoxDecoration(
                        color: fgColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(iconRadius),
                      ),
                      child: Icon(icon, color: fgColor, size: iconGlyph),
                    ),

                    const Spacer(),

                    // Title
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: fgColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 3),

                    // Subtitle
                    Flexible(
                      child: Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: fgColor.withValues(alpha: 0.65),
                          fontSize: 12,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Decide if the given color is "light" (needs dark text).
  bool _isLightColor(Color c) {
    return c.computeLuminance() > 0.45;
  }
}
