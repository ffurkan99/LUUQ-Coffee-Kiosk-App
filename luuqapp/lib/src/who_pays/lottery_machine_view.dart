import 'dart:math';

import 'package:flutter/material.dart';

import 'lottery_simulation.dart';

const _machineBackground = Color(0xFF16131D);
const _machineGold = Color(0xFFF9AB3E);
const _machineCaramel = Color(0xFFD88E2B);
const _machineMint = Color(0xFF48C9B0);
const _machineCream = Color(0xFFFFF7EC);

class WhoPaysLotteryMachineView extends StatelessWidget {
  const WhoPaysLotteryMachineView({
    super.key,
    required this.simulation,
    required this.playerColors,
    required this.repaint,
  });

  final WhoPaysLotterySimulation simulation;
  final List<Color> playerColors;
  final Listenable repaint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      height: 400,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: CustomPaint(painter: _LotteryMachineGlassBackPainter()),
          ),
          RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              willChange: true,
              painter: _LotteryMachineContentPainter(
                simulation: simulation,
                playerColors: List<Color>.unmodifiable(playerColors),
                repaint: repaint,
              ),
            ),
          ),
          const RepaintBoundary(
            child: CustomPaint(painter: _LotteryMachineGlassFrontPainter()),
          ),
        ],
      ),
    );
  }
}

Path _glassPath(Size size) {
  final center = Offset(size.width / 2, 145);
  const radius = 135.0;
  const tubeHalfWidth = 25.0;
  final thetaRight = acos(tubeHalfWidth / radius);
  final thetaLeft = pi - thetaRight;
  final sweepAngle = pi + 2 * thetaRight;
  final start = Offset(
    center.dx - tubeHalfWidth,
    center.dy + radius * sin(thetaLeft),
  );

  return Path()
    ..moveTo(start.dx, start.dy)
    ..arcTo(
      Rect.fromCircle(center: center, radius: radius),
      thetaLeft,
      sweepAngle,
      false,
    )
    ..lineTo(center.dx + tubeHalfWidth, center.dy + 205)
    ..arcTo(
      Rect.fromCircle(
        center: Offset(center.dx, center.dy + 205),
        radius: tubeHalfWidth,
      ),
      0,
      pi,
      false,
    )
    ..lineTo(start.dx, start.dy)
    ..close();
}

class _LotteryMachineGlassBackPainter extends CustomPainter {
  const _LotteryMachineGlassBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 145);
    final path = _glassPath(size);
    final bounds = path.getBounds();

    canvas.drawPath(
      path,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x05FFFFFF), Color(0x14FFFFFF), Color(0x29FFFFFF)],
          stops: [0, 0.7, 1],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      center,
      126,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _machineMint.withValues(alpha: 0.025),
            _machineMint.withValues(alpha: 0.075),
            Colors.transparent,
          ],
          stops: const [0, 0.72, 1],
        ).createShader(Rect.fromCircle(center: center, radius: 126)),
    );
  }

  @override
  bool shouldRepaint(covariant _LotteryMachineGlassBackPainter oldDelegate) {
    return false;
  }
}

class _LotteryMachineContentPainter extends CustomPainter {
  _LotteryMachineContentPainter({
    required this.simulation,
    required this.playerColors,
    required Listenable repaint,
  }) : _numberPainters = List<TextPainter>.generate(
         playerColors.length,
         (index) => TextPainter(
           text: TextSpan(
             text: '${index + 1}',
             style: const TextStyle(
               color: Colors.white,
               fontFamily: 'Roboto',
               fontSize: 18,
               fontWeight: FontWeight.w900,
               shadows: [
                 Shadow(
                   color: Color(0xCC000000),
                   blurRadius: 3,
                   offset: Offset(0, 1),
                 ),
               ],
             ),
           ),
           textDirection: TextDirection.ltr,
           textAlign: TextAlign.center,
         )..layout(),
       ),
       super(repaint: repaint);

  final WhoPaysLotterySimulation simulation;
  final List<Color> playerColors;
  final List<TextPainter> _numberPainters;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 145);
    final glassPath = _glassPath(size);

    canvas.save();
    canvas.clipPath(glassPath);
    _paintRotor(canvas, center);

    final opacity = simulation.contentOpacity.clamp(0.0, 1.0);
    if (opacity < 0.999) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
    for (var index = 0; index < simulation.renderPositions.length; index++) {
      _paintBall(canvas, center, index);
    }
    if (opacity < 0.999) {
      canvas.restore();
    }

    _paintGate(canvas, center);
    canvas.restore();
  }

  void _paintRotor(Canvas canvas, Offset center) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(simulation.rotorAngle);

    final bladePaint = Paint()
      ..color = _machineGold.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;
    final bladeHighlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (var blade = 0; blade < 3; blade++) {
      final angleOffset = blade * 2 * pi / 3;
      final bladePath = Path()
        ..moveTo(0, 0)
        ..cubicTo(
          20 * cos(angleOffset + 0.35),
          20 * sin(angleOffset + 0.35),
          55 * cos(angleOffset + 0.65),
          55 * sin(angleOffset + 0.65),
          85 * cos(angleOffset + 0.4),
          85 * sin(angleOffset + 0.4),
        )
        ..cubicTo(
          55 * cos(angleOffset + 0.1),
          55 * sin(angleOffset + 0.1),
          20 * cos(angleOffset - 0.1),
          20 * sin(angleOffset - 0.1),
          0,
          0,
        );
      canvas
        ..drawPath(bladePath, bladePaint)
        ..drawPath(bladePath, bladeHighlightPaint);
    }

    final capRect = Rect.fromCircle(center: Offset.zero, radius: 15);
    canvas.drawCircle(
      Offset.zero,
      15,
      Paint()
        ..shader = const RadialGradient(
          colors: [_machineCream, _machineGold, _machineCaramel],
          stops: [0, 0.65, 1],
          center: Alignment(-0.3, -0.3),
        ).createShader(capRect),
    );
    canvas.drawCircle(
      Offset.zero,
      15,
      Paint()
        ..color = _machineBackground.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  void _paintBall(Canvas canvas, Offset center, int index) {
    if (index >= playerColors.length || index >= _numberPainters.length) return;

    const radius = WhoPaysLotterySimulation.ballRadius;
    final position = center + simulation.renderPositions[index];
    final color = playerColors[index];
    final bounds = Rect.fromCircle(center: position, radius: radius);

    canvas.drawCircle(
      position + const Offset(2.5, 2.5),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    canvas.drawCircle(
      position,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(color, Colors.white, 0.4)!,
            color,
            Color.lerp(color, Colors.black, 0.3)!,
          ],
          center: const Alignment(-0.35, -0.35),
          radius: 0.9,
        ).createShader(bounds),
    );
    canvas.drawCircle(
      position,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke,
    );

    final numberPainter = _numberPainters[index];
    numberPainter.paint(
      canvas,
      position - Offset(numberPainter.width / 2, numberPainter.height / 2),
    );
  }

  void _paintGate(Canvas canvas, Offset center) {
    const gateHalfWidth = 25.0;
    // Kiriş: cam kürenin tüp duvarlarıyla kesiştiği omuz hattı.
    final chordY = center.dy + sqrt(135.0 * 135.0 - gateHalfWidth * gateHalfWidth);
    final hinge = Offset(center.dx - gateHalfWidth, chordY);
    final angle = pi * 0.5 * simulation.gateProgress;

    canvas.save();
    canvas.translate(hinge.dx, hinge.dy);
    canvas.rotate(angle);
    canvas.drawLine(
      Offset.zero,
      const Offset(gateHalfWidth * 2, 0),
      Paint()
        ..color = _machineBackground.withValues(alpha: 0.75)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset.zero,
      const Offset(gateHalfWidth * 2, 0),
      Paint()
        ..color = _machineGold.withValues(alpha: 0.78)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    canvas.drawCircle(
      hinge,
      5,
      Paint()..color = _machineCaramel.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      hinge,
      5,
      Paint()
        ..color = _machineCream.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _LotteryMachineContentPainter oldDelegate) {
    return oldDelegate.simulation != simulation ||
        oldDelegate.playerColors != playerColors;
  }
}

class _LotteryMachineGlassFrontPainter extends CustomPainter {
  const _LotteryMachineGlassFrontPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 145);
    final path = _glassPath(size);

    canvas.drawPath(
      path,
      Paint()
        ..color = _machineMint.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _machineMint.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(center.dx - 8, center.dy - 8),
        radius: 127,
      ),
      -pi * 0.75,
      pi * 0.4,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(center.dx + 12, center.dy + 10),
        radius: 119,
      ),
      pi * 0.02,
      pi * 0.22,
      false,
      Paint()
        ..color = _machineMint.withValues(alpha: 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _LotteryMachineGlassFrontPainter oldDelegate) {
    return false;
  }
}
