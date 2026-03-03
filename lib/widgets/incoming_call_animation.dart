import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../core/theme/app_theme.dart';

/// Full-screen animation shown when an incoming call is ringing.
class IncomingCallAnimation extends StatefulWidget {
  final String? address;
  final String? contactName;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  /// Seconds until auto-accept (null = no auto-accept).
  final int? autoAcceptSeconds;

  const IncomingCallAnimation({
    super.key,
    this.address,
    this.contactName,
    required this.onAccept,
    required this.onReject,
    this.autoAcceptSeconds,
  });

  @override
  State<IncomingCallAnimation> createState() => _IncomingCallAnimationState();
}

class _IncomingCallAnimationState extends State<IncomingCallAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _ringController;
  late final Animation<double> _ringAnimation;
  late final AnimationController _pulseController;
  int _countdown = 0;

  @override
  void initState() {
    super.initState();

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);

    _ringAnimation = Tween<double>(begin: -0.05, end: 0.05).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeInOut),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    if (widget.autoAcceptSeconds != null) {
      _countdown = widget.autoAcceptSeconds!;
      _startCountdown();
    }
  }

  void _startCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown--);
      if (_countdown <= 0) {
        widget.onAccept();
        return false;
      }
      return true;
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName =
        widget.contactName ?? _truncateOnion(widget.address) ?? S.of(context).unknown;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing rings
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _PulseRingsPainter(
                    progress: _pulseController.value,
                    color: AppColors.mint,
                  ),
                  child: child,
                );
              },
              child: AnimatedBuilder(
                animation: _ringAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _ringAnimation.value,
                    child: child,
                  );
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.mint.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.mint.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.ring_volume,
                    size: 44,
                    color: AppColors.mint,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Title
            Text(
              S.of(context).incomingCall,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.mint,
              ),
            ),

            const SizedBox(height: 12),

            // Caller name
            Text(
              displayName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            // Onion address (if contact name is shown)
            if (widget.contactName != null && widget.address != null) ...[
              const SizedBox(height: 4),
              Text(
                _truncateOnion(widget.address) ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Auto-accept countdown
            if (widget.autoAcceptSeconds != null && _countdown > 0)
              Text(
                S.of(context).autoAnswerCountdown(_countdown),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

            const SizedBox(height: 32),

            // Accept / Reject buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject
                Column(
                  children: [
                    FloatingActionButton(
                      heroTag: 'reject',
                      backgroundColor: theme.colorScheme.error,
                      onPressed: widget.onReject,
                      child: const Icon(Icons.call_end, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).decline,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),

                // Accept
                Column(
                  children: [
                    FloatingActionButton.large(
                      heroTag: 'accept',
                      backgroundColor: AppColors.mint,
                      onPressed: widget.onAccept,
                      child: const Icon(Icons.call, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).answer,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.mint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _truncateOnion(String? addr) {
    if (addr == null) return null;
    if (addr.length > 20) {
      return '${addr.substring(0, 10)}...${addr.substring(addr.length - 10)}';
    }
    return addr;
  }
}

/// Paints expanding concentric rings.
class _PulseRingsPainter extends CustomPainter {
  final double progress;
  final Color color;

  _PulseRingsPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const ringCount = 3;

    for (int i = 0; i < ringCount; i++) {
      final phase = (progress + i / ringCount) % 1.0;
      final radius = 50 + phase * 60;
      final opacity = (1.0 - phase).clamp(0.0, 0.35);

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingsPainter old) =>
      old.progress != progress;
}
