import 'dart:io';

import 'package:flutter/material.dart';

/// Renders bundled assets, cached files, or a remote fallback in that order.
class MenuImageView extends StatelessWidget {
  const MenuImageView({
    super.key,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.assetPath,
    this.remoteImageUrl,
    this.transparentAssetPath,
    this.transparentRemoteImageUrl,
    this.preferTransparent = false,
    this.cacheWidth,
    this.fit = BoxFit.cover,
  });

  final IconData fallbackIcon;
  final Color fallbackColor;
  final String? assetPath;
  final String? remoteImageUrl;
  final String? transparentAssetPath;
  final String? transparentRemoteImageUrl;
  final bool preferTransparent;
  final int? cacheWidth;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final variants = preferTransparent
        ? <(String?, String?)>[
            (transparentAssetPath, transparentRemoteImageUrl),
            (assetPath, remoteImageUrl),
          ]
        : <(String?, String?)>[(assetPath, remoteImageUrl)];
    final sources = <(String?, String?)>[];
    for (final variant in variants) {
      sources.add((variant.$1, null));
      sources.add((null, variant.$2));
    }
    return _buildSource(sources, 0);
  }

  Widget _buildSource(List<(String?, String?)> sources, int index) {
    if (index >= sources.length) {
      return Icon(fallbackIcon, color: fallbackColor, size: 38);
    }
    final (path, url) = sources[index];
    if (path != null && path.isNotEmpty) {
      Widget nextSource(
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
      ) => _buildSource(sources, index + 1);

      return path.startsWith('assets/')
          ? Image.asset(
              path,
              fit: fit,
              cacheWidth: cacheWidth,
              frameBuilder: _fadeIn,
              errorBuilder: nextSource,
            )
          : Image.file(
              File(path),
              fit: fit,
              cacheWidth: cacheWidth,
              frameBuilder: _fadeIn,
              errorBuilder: nextSource,
            );
    }
    if (url != null && Uri.tryParse(url)?.scheme == 'https') {
      return Image.network(
        url,
        fit: fit,
        cacheWidth: cacheWidth,
        frameBuilder: _fadeInOverPlaceholder,
        errorBuilder: (context, error, stack) =>
            _buildSource(sources, index + 1),
      );
    }
    return _buildSource(sources, index + 1);
  }

  /// A photo that is not decoded yet fades in instead of popping into an
  /// empty box; one already in the cache shows at once.
  static Widget _fadeIn(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: child,
    );
  }

  /// [_fadeIn] for a download: a soft glow holds the place until the first
  /// frame arrives.
  static Widget _fadeInOverPlaceholder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (frame == null) const Positioned.fill(child: _LoadingGlow()),
        _fadeIn(context, child, frame, false),
      ],
    );
  }
}

/// A slowly breathing light surface shown while a photo downloads.
class _LoadingGlow extends StatefulWidget {
  const _LoadingGlow();

  @override
  State<_LoadingGlow> createState() => _LoadingGlowState();
}

class _LoadingGlowState extends State<_LoadingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(Tween<double>(begin: 0.03, end: 0.09)),
      child: const ColoredBox(color: Colors.white),
    );
  }
}
