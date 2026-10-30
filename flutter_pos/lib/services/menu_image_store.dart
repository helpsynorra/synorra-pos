import 'dart:collection';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';

/// Raised when a picked product photo cannot be kept on this device.
class MenuImageStoreException implements Exception {
  const MenuImageStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Device-local storage for menu item photos.
///
/// A [MenuItem] keeps a reference in its `image` field. Local references start
/// with [referencePrefix]; any other value is treated as a remote URL.
/// Photos are never uploaded, so the admin panel does not see them and a menu
/// pull from the admin panel replaces them with the admin version.
class MenuImageStore {
  MenuImageStore._();

  static const String referencePrefix = 'local-menu-image:';
  static const String _boxName = 'synorra_menu_images_v1';
  static const int maxPhotoBytes = 5 * 1024 * 1024;
  static const int _memoryCacheLimit = 24;
  static const Set<String> _allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};
  static const Set<String> _allowedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  static Box<Uint8List>? _box;
  static final LinkedHashMap<String, Uint8List> _memoryCache =
      LinkedHashMap<String, Uint8List>();

  static bool isLocalReference(String value) =>
      value.startsWith(referencePrefix);

  static String referenceFor(String key) => '$referencePrefix$key';

  static String? _keyOf(String reference) {
    if (!isLocalReference(reference)) return null;
    final key = reference.substring(referencePrefix.length).trim();
    return key.isEmpty ? null : key;
  }

  static Future<Box<Uint8List>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<Uint8List>(_boxName);
    _box = box;
    return box;
  }

  static void _remember(String key, Uint8List bytes) {
    _memoryCache.remove(key);
    _memoryCache[key] = bytes;
    while (_memoryCache.length > _memoryCacheLimit) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  /// Copies a picked photo into local storage and returns its reference.
  static Future<String> save(XFile file) async {
    final name = file.name.toLowerCase();
    final extension = name.contains('.') ? name.split('.').last : '';
    final mimeType = file.mimeType?.toLowerCase();
    final looksLikePhoto = _allowedExtensions.contains(extension) ||
        (mimeType != null && _allowedMimeTypes.contains(mimeType));
    if (!looksLikePhoto) {
      throw const MenuImageStoreException(
        'Choose a JPG, PNG, or WEBP image.',
      );
    }

    final declaredSize = await file.length();
    if (declaredSize <= 0) {
      throw const MenuImageStoreException(
        'That image is empty. Choose another file.',
      );
    }
    if (declaredSize > maxPhotoBytes) {
      throw const MenuImageStoreException(
        'The image is larger than 5 MB. Choose a smaller file.',
      );
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const MenuImageStoreException(
        'That image is empty. Choose another file.',
      );
    }
    if (bytes.length > maxPhotoBytes) {
      throw const MenuImageStoreException(
        'The image is larger than 5 MB. Choose a smaller file.',
      );
    }

    final digest = sha256.convert(bytes).toString().substring(0, 16);
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final key = '$stamp-$digest';

    try {
      final box = await _openBox();
      await box.put(key, bytes);
      _remember(key, bytes);
      return referenceFor(key);
    } catch (error) {
      throw MenuImageStoreException(
        'Could not save the photo on this device ($error).',
      );
    }
  }

  /// Reads the bytes behind a local reference, or `null` when unavailable.
  static Future<Uint8List?> bytesFor(String reference) async {
    final key = _keyOf(reference);
    if (key == null) return null;

    final cached = _memoryCache.remove(key);
    if (cached != null) {
      _memoryCache[key] = cached;
      return cached;
    }

    try {
      final box = await _openBox();
      final bytes = box.get(key);
      if (bytes == null || bytes.isEmpty) return null;
      _remember(key, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Removes a locally stored photo. Remote URLs are ignored.
  static Future<void> delete(String reference) async {
    final key = _keyOf(reference);
    if (key == null) return;
    _memoryCache.remove(key);
    try {
      final box = await _openBox();
      await box.delete(key);
    } catch (_) {
      // A missing photo is not a reason to fail the menu save.
    }
  }
}
