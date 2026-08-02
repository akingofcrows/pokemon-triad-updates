import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Manages downloading and caching game assets from the server.
/// On first launch, downloads all assets. On subsequent launches,
/// checks the server manifest and only downloads changed files.
class AssetManager {
  AssetManager._();
  static final AssetManager instance = AssetManager._();

  String? _assetDir;
  Map<String, String>? _localManifest;
  bool _downloading = false;
  double _progress = 0;
  String _status = '';

  bool get isDownloading => _downloading;
  double get progress => _progress;
  String get status => _status;

  /// Returns the local path for a given asset relative path.
  /// Example: `assetManager.path('pokemon/BULBASAUR.png')`
  String path(String relativePath) {
    if (_assetDir == null) {
      throw StateError('AssetManager not initialized. Call init() first.');
    }
    return '${_assetDir!}/$relativePath';
  }

  /// Returns true if the asset has been downloaded locally.
  bool exists(String relativePath) {
    if (_assetDir == null) return false;
    return File(path(relativePath)).existsSync();
  }

  /// Initialize the asset manager. Call once at app startup.
  Future<void> init({required String baseUrl}) async {
    final dir = await getApplicationDocumentsDirectory();
    _assetDir = '${dir.path}/game_assets';
    await Directory(_assetDir!).create(recursive: true);

    // Load local manifest
    final manifestFile = File('${_assetDir!}/manifest.json');
    if (manifestFile.existsSync()) {
      try {
        final json = jsonDecode(await manifestFile.readAsString());
        _localManifest = Map<String, String>.from(json['files'] as Map);
      } catch (_) {
        _localManifest = {};
      }
    } else {
      _localManifest = {};
    }
  }

  /// Check for asset updates and download changed files.
  /// Returns true if any files were downloaded.
  Future<bool> syncIfNeeded({required String baseUrl, void Function(double, String)? onProgress}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/assets/manifest'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return false;

      final server = jsonDecode(response.body) as Map<String, dynamic>;
      final serverFiles = Map<String, String>.from(server['files'] as Map);

      // Find changed/new files
      final toDownload = <String>[];
      for (final entry in serverFiles.entries) {
        final localHash = _localManifest?[entry.key];
        if (localHash == null || localHash != entry.value) {
          toDownload.add(entry.key);
        }
      }

      if (toDownload.isEmpty) {
        debugPrint('AssetManager: all ${serverFiles.length} assets up to date');
        return false;
      }

      debugPrint('AssetManager: downloading ${toDownload.length} changed assets');
      _downloading = true;
      _progress = 0;
      onProgress?.call(0, 'Updating assets…');

      int downloaded = 0;
      for (final file in toDownload) {
        _status = 'Downloading $file…';
        onProgress?.call(downloaded / toDownload.length, _status);

        try {
          final resp = await http.get(
            Uri.parse('$baseUrl/api/assets/$file'),
            headers: {'ngrok-skip-browser-warning': 'true'},
          ).timeout(const Duration(seconds: 15));

          if (resp.statusCode == 200) {
            final localPath = '${_assetDir!}/$file';
            await Directory(localPath).parent.create(recursive: true);
            await File('${_assetDir!}/$file').writeAsBytes(resp.bodyBytes);
          }
        } catch (e) {
          debugPrint('AssetManager: failed to download $file: $e');
        }

        downloaded++;
        _progress = downloaded / toDownload.length;
        onProgress?.call(_progress, _status);
      }

      // Save updated manifest
      final newManifest = {'version': 1, 'files': serverFiles};
      await File('${_assetDir!}/manifest.json')
          .writeAsString(jsonEncode(newManifest));
      _localManifest = serverFiles;

      _downloading = false;
      onProgress?.call(1, 'Assets up to date!');
      return true;
    } catch (e) {
      debugPrint('AssetManager: sync failed: $e');
      _downloading = false;
      return false;
    }
  }

  /// Force download all assets (for first-time setup).
  Future<void> downloadAll({required String baseUrl, void Function(double, String)? onProgress}) async {
    await syncIfNeeded(baseUrl: baseUrl, onProgress: onProgress);
  }
}
