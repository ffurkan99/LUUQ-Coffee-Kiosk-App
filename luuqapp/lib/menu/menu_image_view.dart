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
              errorBuilder: nextSource,
            )
          : Image.file(
              File(path),
              fit: fit,
              cacheWidth: cacheWidth,
              errorBuilder: nextSource,
            );
    }
    if (url != null && Uri.tryParse(url)?.scheme == 'https') {
      return Image.network(
        url,
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (context, error, stack) =>
            _buildSource(sources, index + 1),
      );
    }
    return _buildSource(sources, index + 1);
  }
}
