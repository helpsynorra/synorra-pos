import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/menu_image_store.dart';
import 'offline_cached_image.dart';

/// Renders a menu item photo from any of the sources the POS supports:
///
/// * `local-menu-image:` references saved on this device (see MenuImageStore)
/// * remote URLs uploaded from the admin panel
/// * an empty value, which falls back to the cafe icon placeholder
class MenuItemImage extends StatelessWidget {
  final String image;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;

  const MenuItemImage({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
  });

  Widget get _fallback =>
      placeholder ??
      const Icon(
        Icons.local_cafe_outlined,
        color: Color(0xFF9CA3AF),
      );

  @override
  Widget build(BuildContext context) {
    final source = image.trim();
    if (source.isEmpty) return _fallback;

    if (MenuImageStore.isLocalReference(source)) {
      return FutureBuilder<Uint8List?>(
        future: MenuImageStore.bytesFor(source),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) return _fallback;
          return Image.memory(
            bytes,
            fit: fit,
            width: width,
            height: height,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => _fallback,
          );
        },
      );
    }

    if (kIsWeb) {
      return Image.network(
        source,
        fit: fit,
        width: width,
        height: height,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _fallback,
      );
    }

    return OfflineCachedImage(
      url: source,
      fit: fit,
      width: width,
      height: height,
      placeholder: _fallback,
      errorWidget: _fallback,
    );
  }
}
