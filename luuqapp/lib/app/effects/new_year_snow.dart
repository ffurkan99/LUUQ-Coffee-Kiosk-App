part of '../../main.dart';

// ===== YILBAŞI MODU KAR YAĞMURU WIDGETI VE PAINTERI =====

class _NewYearThemeSnowRain extends StatefulWidget {
  const _NewYearThemeSnowRain();

  @override
  State<_NewYearThemeSnowRain> createState() => _NewYearThemeSnowRainState();
}

class _NewYearThemeSnowRainState extends State<_NewYearThemeSnowRain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_SnowParticle> _particles = [];
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
    for (int i = 0; i < 50; i++) {
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

  _SnowParticle _generateParticle({bool initial = false}) {
    final scale = 0.4 + _random.nextDouble() * 0.8;
    return _SnowParticle(
      x: _random.nextDouble(),
      y: initial ? _random.nextDouble() * 1.2 - 0.2 : -0.1,
      speed: 0.03 + _random.nextDouble() * 0.05, // Same speed as candy rain
      rotation: _random.nextDouble() * pi * 2,
      rotationSpeed:
          (0.1 + _random.nextDouble() * 0.3) * (_random.nextBool() ? 1 : -1),
      scale: scale,
      opacity: 0.3 + _random.nextDouble() * 0.5,
      type: _random.nextInt(
        3,
      ), // 0: soft circle, 1: asterisk, 2: complex crystal
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
      p.y += p.speed * 0.05 * f; // Same fall speed factor as candy rain
      p.rotation += p.rotationSpeed * 0.05 * f; // Spin speed

      // Sway sideways slightly like real snow
      p.x += sin(_controller.value * pi * 2 + i) * 0.0012 * f;

      // Reset if it goes off bottom
      if (p.y > 1.1) {
        _particles[i] = _generateParticle();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Own layer: the snow repaints every frame without making the rest of
    // the screen repaint with it.
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SnowRainPainter(
              particles: _particles,
              repaint: _controller,
            ),
          ),
        ),
      ),
    );
  }
}

class _SnowParticle {
  double x; // 0.0 to 1.0
  double y; // 0.0 to 1.0
  final double speed;
  double rotation;
  final double rotationSpeed;
  final double scale;
  final double opacity;
  final int type; // 0: soft circle, 1: asterisk, 2: complex crystal

  _SnowParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.scale,
    required this.opacity,
    required this.type,
  });
}

class _SnowRainPainter extends CustomPainter {
  final List<_SnowParticle> particles;
  _SnowRainPainter({required this.particles, required Listenable repaint})
    : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final px = p.x * size.width;
      final py = p.y * size.height;
      final radius = 12.0 * p.scale;

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.rotation);

      if (p.type == 0) {
        // Draw Soft Circle
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: p.opacity)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset.zero, radius * 0.7, paint);
      } else if (p.type == 1) {
        // Draw 6-pointed asterisk
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: p.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * p.scale
          ..strokeCap = StrokeCap.round;

        for (int i = 0; i < 3; i++) {
          final angle = i * pi / 3;
          canvas.drawLine(
            Offset(-radius * cos(angle), -radius * sin(angle)),
            Offset(radius * cos(angle), radius * sin(angle)),
            paint,
          );
        }
      } else {
        // Draw complex branched snow crystal
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: p.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * p.scale
          ..strokeCap = StrokeCap.round;

        for (int i = 0; i < 6; i++) {
          final angle = i * pi / 3;
          final endX = radius * cos(angle);
          final endY = radius * sin(angle);
          canvas.drawLine(Offset.zero, Offset(endX, endY), paint);

          // Branches
          final branchLength = radius * 0.35;
          final branchAngle = pi / 4.5; // ~40 degrees

          // Branches at 50% length
          final bx1 = endX * 0.5;
          final by1 = endY * 0.5;
          canvas.drawLine(
            Offset(bx1, by1),
            Offset(
              bx1 + branchLength * cos(angle + branchAngle),
              by1 + branchLength * sin(angle + branchAngle),
            ),
            paint,
          );
          canvas.drawLine(
            Offset(bx1, by1),
            Offset(
              bx1 + branchLength * cos(angle - branchAngle),
              by1 + branchLength * sin(angle - branchAngle),
            ),
            paint,
          );

          // Small tips at 80% length
          final bx2 = endX * 0.8;
          final by2 = endY * 0.8;
          final smallTipLength = branchLength * 0.6;
          canvas.drawLine(
            Offset(bx2, by2),
            Offset(
              bx2 + smallTipLength * cos(angle + branchAngle),
              by2 + smallTipLength * sin(angle + branchAngle),
            ),
            paint,
          );
          canvas.drawLine(
            Offset(bx2, by2),
            Offset(
              bx2 + smallTipLength * cos(angle - branchAngle),
              by2 + smallTipLength * sin(angle - branchAngle),
            ),
            paint,
          );
        }
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SnowRainPainter oldDelegate) => true;
}

// ===== YILBAŞI MODU NOEL ŞAPKASI PAINTERI =====

class _SantaHatPainter extends CustomPainter {
  const _SantaHatPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Draw red cap body (curved cone/triangle)
    final redPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF981B35), // Velvet shadow
          const Color(0xFFDF354B), // Red fabric
          const Color(0xFFF06469), // Soft rim light
        ],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    // Curved red hat path
    final hatPath = Path();
    // Start at bottom-left of the red part
    hatPath.moveTo(w * 0.15, h * 0.7);
    // Control point for the top curve of the hat
    hatPath.cubicTo(w * 0.19, h * 0.39, w * 0.30, h * 0.12, w * 0.53, h * 0.14);
    // Tip of the hat dropping down slightly
    hatPath.cubicTo(w * 0.76, h * 0.12, w * 0.88, h * 0.29, w * 0.85, h * 0.49);
    // Inner fold curve back to bottom-right
    hatPath.cubicTo(w * 0.77, h * 0.47, w * 0.71, h * 0.34, w * 0.62, h * 0.33);
    hatPath.cubicTo(w * 0.64, h * 0.43, w * 0.71, h * 0.56, w * 0.78, h * 0.70);
    hatPath.close();

    // Draw shadow under the hat body
    canvas.drawPath(
      hatPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );

    canvas.drawPath(hatPath, redPaint);

    // Draw white fluffy brim at the bottom
    final whiteBrimPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFFFFFCF4), const Color(0xFFE0DED9)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, h * 0.62, w, h * 0.2))
      ..style = PaintingStyle.fill;

    // Brim as a soft curved path
    final brimPath = Path();
    brimPath.moveTo(w * 0.12, h * 0.65);
    brimPath.quadraticBezierTo(w * 0.45, h * 0.59, w * 0.78, h * 0.65);
    brimPath.cubicTo(
      w * 0.86,
      h * 0.66,
      w * 0.86,
      h * 0.80,
      w * 0.78,
      h * 0.81,
    );
    brimPath.quadraticBezierTo(w * 0.45, h * 0.77, w * 0.12, h * 0.81);
    brimPath.cubicTo(
      w * 0.04,
      h * 0.81,
      w * 0.04,
      h * 0.66,
      w * 0.12,
      h * 0.65,
    );
    brimPath.close();

    // Brim shadow
    canvas.drawPath(
      brimPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );
    canvas.drawPath(brimPath, whiteBrimPaint);

    // Draw small circles/bumps along the brim for fluffy details
    final fluffPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw pom-pom at the tip
    final pomPomCenter = Offset(w * 0.85, h * 0.50);
    final pomPomRadius = w * 0.095;
    // Pom-pom shadow
    canvas.drawCircle(
      pomPomCenter,
      pomPomRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );
    // Draw pom-pom base
    canvas.drawCircle(pomPomCenter, pomPomRadius, fluffPaint);

    // Draw smaller overlay circles for pom-pom fluffiness
    canvas.drawCircle(
      pomPomCenter + Offset(-w * 0.02, -h * 0.02),
      pomPomRadius * 0.40,
      Paint()..color = const Color(0xFFFFFEF8),
    );
    canvas.drawCircle(
      pomPomCenter + Offset(w * 0.02, h * 0.02),
      pomPomRadius * 0.24,
      Paint()..color = const Color(0xFFECE9E2),
    );
  }

  @override
  bool shouldRepaint(covariant oldDelegate) => false;
}
