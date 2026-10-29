import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/staff_user.dart';
import '../../services/offline_image_cache.dart';

class OfflineStaffAvatar extends StatefulWidget {
  final StaffUser staff;
  final Future<String?> Function(String staffUserId) resolveSignedUrl;
  final double radius;

  const OfflineStaffAvatar({
    super.key,
    required this.staff,
    required this.resolveSignedUrl,
    this.radius = 18,
  });

  @override
  State<OfflineStaffAvatar> createState() => _OfflineStaffAvatarState();
}

class _OfflineStaffAvatarState extends State<OfflineStaffAvatar> {
  File? _file;

  String get _cacheKey =>
      OfflineImageCache.staffAvatarCacheKey(widget.staff.avatarPath ?? '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OfflineStaffAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.staff.avatarPath != widget.staff.avatarPath ||
        oldWidget.staff.id != widget.staff.id) {
      _file = null;
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.staff.avatarPath?.trim();
    if (path == null || path.isEmpty) return;
    final cacheKey = _cacheKey;
    final cached = await OfflineImageCache.cachedFileForCacheKey(cacheKey);
    if (!mounted || cacheKey != _cacheKey) return;
    if (cached != null) {
      setState(() => _file = cached);
      return;
    }

    final signedUrl = await widget.resolveSignedUrl(widget.staff.id);
    if (!mounted || cacheKey != _cacheKey || signedUrl == null) return;
    final file = await OfflineImageCache.cacheImage(
      signedUrl,
      cacheKey: cacheKey,
    );
    if (!mounted || cacheKey != _cacheKey) return;
    if (file != null) setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file != null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundImage: FileImage(file),
      );
    }
    return CircleAvatar(
      radius: widget.radius,
      child: Text(
        widget.staff.name.isEmpty ? '?' : widget.staff.name[0].toUpperCase(),
      ),
    );
  }
}
