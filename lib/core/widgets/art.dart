import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';

/// The app's illustrations (assets/illustrations) and animations
/// (assets/lottie). One flat style in the brand palette: navy, brand blue,
/// periwinkle, amber and coral. Use them for moments (sign-in, welcome,
/// empty and all-done states), never as decoration on working screens.
class Art {
  Art._();

  static const siteSkyline = 'assets/illustrations/site_skyline.svg';
  static const heroLines = 'assets/illustrations/hero_lines.svg';
  static const emptyBlueprint = 'assets/illustrations/empty_blueprint.svg';
  static const allClear = 'assets/illustrations/all_clear.svg';
  static const emptyPlot = 'assets/illustrations/empty_plot.svg';

  static const buildingRise = 'assets/lottie/building_rise.json';
  static const successCheck = 'assets/lottie/success_check.json';
}

/// An SVG illustration at a fixed height.
class Illustration extends StatelessWidget {
  const Illustration(
    this.asset, {
    super.key,
    this.height = 140,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
  });

  final String asset;
  final double height;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(asset, height: height, fit: fit, alignment: alignment);
}

/// A Lottie animation. Respects the system's reduce-motion setting by
/// showing the finished frame instead of playing.
class AppAnimation extends StatefulWidget {
  const AppAnimation(this.asset, {super.key, this.size = 120, this.repeat = false});

  /// Blocks rising, for loading.
  const AppAnimation.loading({super.key, this.size = 120})
      : asset = Art.buildingRise,
        repeat = true;

  /// A tick drawing itself, for "done" moments.
  const AppAnimation.success({super.key, this.size = 72})
      : asset = Art.successCheck,
        repeat = false;

  final String asset;
  final double size;
  final bool repeat;

  @override
  State<AppAnimation> createState() => _AppAnimationState();
}

class _AppAnimationState extends State<AppAnimation> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Lottie.asset(
        widget.asset,
        controller: _controller,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        onLoaded: (composition) {
          _controller.duration = composition.duration;
          final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
          if (still) {
            _controller.value = widget.repeat ? 0.5 : 1;
          } else if (widget.repeat) {
            _controller.repeat();
          } else {
            _controller.forward();
          }
        },
      );
}
