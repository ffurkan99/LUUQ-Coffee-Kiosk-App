part of '../../main.dart';

/// Background blur behind customer dialogs. Set to 0 if a kiosk tablet
/// stutters while a dialog is open; the dark scrim stays.
const double _kioskDialogBlur = 10;

/// A light spring: the dialog settles with one small (~4 %) overshoot.
class _KioskSpringCurve extends Curve {
  const _KioskSpringCurve();

  static const double seconds = 0.38;
  static final SpringSimulation _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: 0.72),
    0,
    1,
    0,
  );

  @override
  double transformInternal(double t) => _spring.x(t * seconds);
}

/// The route every customer dialog (menu, product detail, Who Pays, locked
/// feature) opens with: a spring scale-in over a blurred, darkened kiosk.
///
/// It is a [PageRoute], so a [Hero] (for example a product photo) can fly
/// from the screen below into the dialog.
class _KioskDialogRoute<T> extends PageRoute<T> {
  _KioskDialogRoute({
    required this.child,
    required this.label,
    required this.dismissible,
    required this.instant,
    required this.scrimOpacity,
  });

  final Widget child;
  final String label;
  final bool dismissible;
  final bool instant;
  final double scrimOpacity;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false; // The scrim below handles taps.

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => label;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => instant
      ? Duration.zero
      : Duration(milliseconds: (_KioskSpringCurve.seconds * 1000).round());

  @override
  Duration get reverseTransitionDuration =>
      instant ? Duration.zero : const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: label,
          button: dismissible,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: dismissible ? () => Navigator.of(context).maybePop() : null,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = animation.value.clamp(0.0, 1.0);
                final scrim = ColoredBox(
                  color: Colors.black.withValues(alpha: scrimOpacity * t),
                );
                if (_kioskDialogBlur <= 0 || t == 0) return scrim;
                return BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: _kioskDialogBlur * t,
                    sigmaY: _kioskDialogBlur * t,
                  ),
                  child: scrim,
                );
              },
            ),
          ),
        ),
        FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0, 0.5, curve: Curves.easeOut),
            reverseCurve: Curves.easeInCubic,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(
              CurvedAnimation(
                parent: animation,
                curve: const _KioskSpringCurve(),
                reverseCurve: Curves.easeInCubic,
              ),
            ),
            child: _VirtualCanvasDialogWrapper(
              // Taps inside the dialog must not reach the scrim.
              child: GestureDetector(onTap: () {}, child: child),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child; // buildPage animates the scrim and the dialog separately.
}

/// Opens [child] as a customer dialog (see [_KioskDialogRoute]). A dialog
/// opened over another one darkens the screen less, so the two scrims do not
/// stack into black.
Future<T?> _showKioskDialog<T>(
  BuildContext context,
  Widget child, {
  required String label,
  bool barrierDismissible = true,
}) {
  final overDialog = ModalRoute.of(context) is _KioskDialogRoute;
  return Navigator.of(context).push<T>(
    _KioskDialogRoute<T>(
      child: child,
      label: label,
      dismissible: barrierDismissible,
      instant: MediaQuery.disableAnimationsOf(context),
      scrimOpacity: overDialog ? 0.25 : 0.45,
    ),
  );
}
