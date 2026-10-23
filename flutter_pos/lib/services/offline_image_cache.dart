import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Persistent cache for remote POS images so previously synced products remain
/// visible when the device has no network connection.
class OfflineImageCache {
  OfflineImageCache._();

  static final Map<String, Future<File?>> _pending = {};

  static Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}pos_images',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static Uri? _uriFor(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  // Image URLs may contain short-lived signed query parameters. Ignore those
  // when creating the cache key so the same image remains addressable later.
  static String _keyFor(Uri uri) {
    const temporaryKeys = {
      'token',
      'signature',
      'expires',
      'x-amz-signature',
      'x-amz-credential',
      'x-amz-date',
      'x-amz-expires',
      'x-amz-security-token',
      'x-goog-signature',
      'x-goog-credential',
      'x-goog-date',
      'x-goog-expires',
    };
    final kept = <String, String>{};
    uri.queryParameters.forEach((key, value) {
      if (!temporaryKeys.contains(key.toLowerCase())) kept[key] = value;
    });
    final stableUri = uri.replace(
      queryParameters: kept.isEmpty ? null : kept,
      fragment: '',
    );
    return sha256.convert(stableUri.toString().codeUnits).toString();
  }

  static Future<File?> cachedFileFor(String url) async {
    final uri = _uriFor(url);
    if (uri == null) return null;
    try {
      final file = File(
        '${(await _directory()).path}${Platform.pathSeparator}${_keyFor(uri)}',
      );
      return await file.exists() && await file.length() > 0 ? file : null;
    } catch (error) {
      debugPrint('Could not read cached POS image: $error');
      return null;
    }
  }

  static Future<File?> cacheImage(String url) async {
    final uri = _uriFor(url);
    if (uri == null) return null;
    final key = _keyFor(uri);
    final running = _pending[key];
    if (running != null) return running;
    final future = _download(uri, key);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  static Future<File?> _download(Uri uri, String key) async {
    File? temporary;
    try {
      final directory = await _directory();
      final file = File('${directory.path}${Platform.pathSeparator}$key');
      if (await file.exists() && await file.length() > 0) return file;

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      if (await file.exists()) await file.delete();
      return await temporary.rename(file.path);
    } catch (error) {
      debugPrint('Could not cache POS image: $error');
      return null;
    } finally {
      if (temporary != null && await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> cacheUrls(Iterable<String> urls) async {
    final unique = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet();
    await Future.wait(unique.map(cacheImage));
  }
}
