part of '../../main.dart';

// ===== BAYRAM MODU ŞEKER YAĞMURU WIDGETI VE PAINTERI =====

/// How many 60 Hz frames passed between two animation ticks, so particles
/// move at the same speed on 60 and 120 Hz screens and do not jump after a
/// stall (capped at 6 frames = 0.1 s). A restarted controller (elapsed time
/// going back) counts as one frame.
@visibleForTesting
double effectFrameFactor(Duration? previous, Duration? current) {
  if (previous == null || current == null) return 1;
  final seconds = (current - previous).inMicroseconds / 1e6;
  if (seconds <= 0) return 1;
  return min(seconds, 0.1) * 60;
}

class _FeastThemeCandyRain extends StatefulWidget {
  final int count;
  const _FeastThemeCandyRain({this.count = 40});

  @override
  State<_FeastThemeCandyRain> createState() => _FeastThemeCandyRainState();
}

class _FeastThemeCandyRainState extends State<_FeastThemeCandyRain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_CandyParticle> _particles = [];
  final Random _random = Random();
  Duration? _lastTick;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // Initialize particles
    for (int i = 0; i < widget.count; i++) {
      _particles.add(_generateParticle(initial: true));
    }

    _controller.addListener(_updateParticles);
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
    _controller.removeListener(_updateParticles);
    _controller.dispose();
    super.dispose();
  }

  _CandyParticle _generateParticle({bool initial = false}) {
    final scale = 0.5 + _random.nextDouble() * 0.7;
    return _CandyParticle(
      x: _random.nextDouble(),
      y: initial ? _random.nextDouble() * 1.2 - 0.2 : -0.1,
      speed: 0.03 + _random.nextDouble() * 0.05,
      rotation: _random.nextDouble() * pi * 2,
      rotationSpeed:
          (0.2 + _random.nextDouble() * 0.6) * (_random.nextBool() ? 1 : -1),
      scale: scale,
      color: [
        const Color(0xFFFF74B1), // Candy Pink
        const Color(0xFFFFB100), // Orange
        const Color(0xFF48C9B0), // Mint
        const Color(0xFFFF7D7D), // Soft Red
        const Color(0xFFA55EEA), // Purple
        const Color(0xFF2D98DA), // Blue
      ][_random.nextInt(6)],
      type: _random.nextInt(
        3,
      ), // 0: Wrapped Hard Candy, 1: Lollipop, 2: Round Swirl
    );
  }

  // setState yok: painter _controller'a repaint ile bağlı; burada yalnızca
  // parçacık konumları güncellenir, widget ağacı yeniden kurulmaz.
  void _updateParticles() {
    final tick = _controller.lastElapsedDuration;
    final f = effectFrameFactor(_lastTick, tick);
    _lastTick = tick;
    for (int i = 0; i < _particles.length; i++) {
      final p = _particles[i];
      p.y += p.speed * 0.05 * f; // Fall speed
      p.rotation += p.rotationSpeed * 0.05 * f; // Spin speed

      // Horizontal sway
      p.x += sin(_controller.value * pi * 2 + i) * 0.001 * f;

      // Reset if it goes off bottom
      if (p.y > 1.1) {
        _particles[i] = _generateParticle();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Own layer: the falling candies repaint every frame without making the
    // rest of the screen repaint with them.
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _CandyRainPainter(
              particles: _particles,
              repaint: _controller,
            ),
          ),
        ),
      ),
    );
  }
}

class _CandyParticle {
  double x; // 0.0 to 1.0
  double y; // 0.0 to 1.0
  final double speed;
  double rotation;
  final double rotationSpeed;
  final double scale;
  final Color color;
  final int type; // 0: wrapped candy, 1: lollipop, 2: round swirl

  _CandyParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.scale,
    required this.color,
    required this.type,
  });
}

class _CandyRainPainter extends CustomPainter {
  final List<_CandyParticle> particles;
  _CandyRainPainter({required this.particles, required Listenable repaint})
    : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final px = p.x * size.width;
      final py = p.y * size.height;
      final radius = 16.0 * p.scale;

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.rotation);

      if (p.type == 0) {
        // Draw Wrapped Hard Candy
        // Left twist end
        final pathLeft = Path()
          ..moveTo(-radius, 0)
          ..lineTo(-radius * 1.6, -radius * 0.6)
          ..lineTo(-radius * 1.6, radius * 0.6)
          ..close();
        paint.color = p.color.withValues(alpha: 0.7);
        canvas.drawPath(pathLeft, paint);

        // Right twist end
        final pathRight = Path()
          ..moveTo(radius, 0)
          ..lineTo(radius * 1.6, -radius * 0.6)
          ..lineTo(radius * 1.6, radius * 0.6)
          ..close();
        canvas.drawPath(pathRight, paint);

        // Central candy body
        paint.color = p.color;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: radius * 2,
            height: radius * 1.3,
          ),
          paint,
        );

        // Swirl line/details
        final detailPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * p.scale;
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset.zero,
            width: radius * 1.2,
            height: radius * 0.8,
          ),
          0,
          pi,
          false,
          detailPaint,
        );
      } else if (p.type == 1) {
        // Draw Lollipop
        // Stick
        final stickPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 * p.scale
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset.zero, Offset(0, radius * 1.8), stickPaint);

        // Lollipop head
        paint.color = p.color;
        canvas.drawCircle(Offset.zero, radius, paint);

        // Swirl detail
        final swirlPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * p.scale;

        final swirlPath = Path();
        for (double theta = 0; theta < pi * 3; theta += 0.1) {
          final r = radius * 0.8 * (theta / (pi * 3));
          final dx = r * cos(theta);
          final dy = r * sin(theta);
          if (theta == 0) {
            swirlPath.moveTo(dx, dy);
          } else {
            swirlPath.lineTo(dx, dy);
          }
        }
        canvas.drawPath(swirlPath, swirlPaint);
      } else {
        // Draw Round Swirl Candy
        paint.color = p.color;
        canvas.drawCircle(Offset.zero, radius, paint);

        // Stripes details
        final stripePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * p.scale;

        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * 0.7),
          0,
          pi * 0.5,
          false,
          stripePaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * 0.7),
          pi,
          pi * 0.5,
          false,
          stripePaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * 0.4),
          pi * 0.5,
          pi * 0.5,
          false,
          stripePaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * 0.4),
          pi * 1.5,
          pi * 0.5,
          false,
          stripePaint,
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CandyRainPainter oldDelegate) => true;
}
