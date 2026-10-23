import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/offline_image_cache.dart';

class OfflineCachedImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget placeholder;
  final Widget errorWidget;

  const OfflineCachedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    required this.placeholder,
    required this.errorWidget,
  });

  @override
  State<OfflineCachedImage> createState() => _OfflineCachedImageState();
}

class _OfflineCachedImageState extends State<OfflineCachedImage> {
  File? _file;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant OfflineCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _file = null;
      _loading = true;
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final url = widget.url;
    final cached = await OfflineImageCache.cachedFileFor(url);
    if (!mounted || url != widget.url) return;
    if (cached != null) setState(() => _file = cached);

    final downloaded = await OfflineImageCache.cacheImage(url);
    if (!mounted || url != widget.url) return;
    setState(() {
      _file = downloaded ?? cached;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file != null) {
      return Image.file(
        file,
        key: ValueKey(file.path),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (_, __, ___) => widget.errorWidget,
      );
    }
    return _loading ? widget.placeholder : widget.errorWidget;
  }
}
