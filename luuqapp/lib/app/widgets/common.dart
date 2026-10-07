part of '../../main.dart';

class BouncyButton extends StatefulWidget {
  const BouncyButton({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<BouncyButton>
    with SingleTickerProviderStateMixin {
  bool _showFocusHighlight = false;
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (widget.onTap != null && !MediaQuery.disableAnimationsOf(context)) {
          _controller.forward();
        }
      },
      onPointerUp: (_) {
        if (widget.onTap != null && !MediaQuery.disableAnimationsOf(context)) {
          _controller.reverse();
        }
      },
      onPointerCancel: (_) {
        if (widget.onTap != null && !MediaQuery.disableAnimationsOf(context)) {
          _controller.reverse();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: FocusableActionDetector(
          enabled: widget.onTap != null,
          mouseCursor: widget.onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onShowFocusHighlight: (value) {
            if (mounted) setState(() => _showFocusHighlight = value);
          },
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                final onTap = widget.onTap;
                if (onTap != null) {
                  if (!MediaQuery.disableAnimationsOf(context)) {
                    _controller.forward().then((_) {
                      if (mounted) _controller.reverse();
                    });
                  }
                  onTap();
                }
                return null;
              },
            ),
          },
          child: Semantics(
            button: true,
            enabled: widget.onTap != null,
            child: ScaleTransition(
              scale: MediaQuery.disableAnimationsOf(context)
                  ? const AlwaysStoppedAnimation<double>(1)
                  : _scaleAnimation,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: _showFocusHighlight && widget.onTap != null
                      ? Border.all(color: _cream, width: 2)
                      : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CurvedArrowsPainter extends CustomPainter {
  final double animationValue;
  _CurvedArrowsPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    // Synchronize opacity and a subtle radial pulse for a true 'breathing' feel
    final double baseRadius = size.width * 0.48;
    final double radius =
        baseRadius + (animationValue * 4.0); // Subtle expansion pulse

    final center = Offset(size.width / 2, size.height / 2);
    final Rect arcRect = Rect.fromCircle(center: center, radius: radius);

    // Opacity pulse - kept subtle so arrows don't dominate
    final color = Colors.white.withValues(
      alpha: 0.10 + (animationValue * 0.30),
    );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.butt;

    final arrowHeadPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 1. Left-side curved arrow (around 9-10 o'clock)
    const double startAngle1 = -pi * 0.60;
    const double sweepAngle1 = -pi * 0.22;
    canvas.drawArc(arcRect, startAngle1, sweepAngle1, false, paint);

    // 2. Right-side curved arrow (around 4-5 o'clock)
    const double startAngle2 = pi * 0.42;
    const double sweepAngle2 = -pi * 0.22;
    canvas.drawArc(arcRect, startAngle2, sweepAngle2, false, paint);

    // Function to draw arrow head at the end of an arc
    void drawHead(double endAngle) {
      final double x = center.dx + radius * cos(endAngle);
      final double y = center.dy + radius * sin(endAngle);

      canvas.save();
      canvas.translate(x, y);

      final double tangentAngle = atan2(-cos(endAngle), sin(endAngle));
      canvas.rotate(tangentAngle - pi / 2);

      final headPath = Path()
        ..moveTo(-8, -14)
        ..lineTo(8, -14)
        ..lineTo(0, 0)
        ..close();
      canvas.drawPath(headPath, arrowHeadPaint);
      canvas.restore();
    }

    // Draw heads at the end of each arc
    drawHead(startAngle1 + sweepAngle1);
    drawHead(startAngle2 + sweepAngle2);
  }

  @override
  bool shouldRepaint(covariant _CurvedArrowsPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

class _RotatingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _RotatingIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  @override
  State<_RotatingIcon> createState() => _RotatingIconState();
}

class _RotatingIconState extends State<_RotatingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}

/// The close button of every customer dialog: a 52 px glass circle with an X.
/// It pops the dialog.
class _KioskCloseButton extends StatelessWidget {
  const _KioskCloseButton({super.key, this.semanticLabel});

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel ?? tr('Kapat', 'Close'),
      excludeSemantics: true,
      child: BouncyButton(
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Icon(
            Icons.close_rounded,
            color: Colors.white70,
            size: 26,
          ),
        ),
      ),
    );
  }
}

/// [card] with the [_KioskCloseButton] in its top-right corner, inside the
/// card's rounded edge.
Widget _withKioskCloseButton(
  Widget card, {
  Key? closeKey,
  String? semanticLabel,
}) {
  return Stack(
    children: [
      card,
      Positioned(
        top: 16,
        right: 16,
        child: _KioskCloseButton(key: closeKey, semanticLabel: semanticLabel),
      ),
    ],
  );
}

class _VirtualCanvasDialogWrapper extends StatelessWidget {
  final Widget child;
  const _VirtualCanvasDialogWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenAspectRatio = constraints.maxWidth / constraints.maxHeight;
        final virtualWidth = max(1920.0, 1080.0 * screenAspectRatio);

        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(size: Size(virtualWidth, 1080.0)),
              child: SizedBox(
                width: virtualWidth,
                height: 1080.0,
                child: Center(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      if (GlobalDialogTracker.isAdminSessionOpen) {
                        _CafeKioskScreenState.resetTimer();
                      }
                    },
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LanguageSwitcher extends StatelessWidget {
  const _LanguageSwitcher();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, language, _) {
        final isTr = language == AppLanguage.tr;
        return BouncyButton(
          onTap: () {
            if (isTr && !currentFeatureFlags.english) {
              showFeatureLockedDialog(
                context,
                tr('İngilizce Dil Desteği', 'English Language Support'),
              );
              return;
            }
            appLanguageNotifier.value = isTr ? AppLanguage.en : AppLanguage.tr;
          },
          child: Container(
            decoration: BoxDecoration(
              color: _bgDark.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TR',
                  style: TextStyle(
                    color: isTr ? _gold : _mutedText,
                    fontWeight: isTr ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 16,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 8),
                Text(
                  'EN',
                  style: TextStyle(
                    color: !isTr ? _gold : _mutedText,
                    fontWeight: !isTr ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
