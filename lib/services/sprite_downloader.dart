import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Extracts the bundled `sprite_bundle.zip` to device storage on first
/// launch so evolution sprites can be loaded via `Image.file()`.
class SpriteDownloader {
  SpriteDownloader._();
  static final SpriteDownloader instance = SpriteDownloader._();

  static const _targetDir = 'tt_sprites';
  static const _bundleAsset = 'assets/sprite_bundle.zip';
  static const _version = 'v2'; // bump to force re-extract

  double progress = 0;
  String status = '';

  /// Whether sprites have already been extracted.
  Future<bool> get isReady async {
    final dir = await _targetDirectory;
    final marker = File('${dir.path}/.ready_$_version');
    return marker.exists();
  }

  Future<Directory> get _targetDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_targetDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Extracts the sprite bundle, reporting progress via [onProgress].
  /// Skips extraction if already done.
  Future<void> download({void Function(double progress, String status)? onProgress}) async {
    if (await isReady) {
      onProgress?.call(1.0, 'Sprites ready');
      return;
    }

    onProgress?.call(0.0, 'Loading sprite bundle…');

    // Load the ZIP from assets.
    final data = await rootBundle.load(_bundleAsset);
    final bytes = Uint8List.view(
      data.buffer,
      data.offsetInBytes,
      data.lengthInBytes,
    );

    onProgress?.call(0.1, 'Extracting ${(bytes.length / 1024).round()} KB…');

    final targetDir = await _targetDirectory;

    // Clean old corrupt sprites, then extract fresh.
    final frontDir = Directory('${targetDir.path}/front');
    if (await frontDir.exists()) {
      await frontDir.delete(recursive: true);
    }

    // Decode ZIP using the archive package (handles DEFLATE properly).
    final archive = ZipDecoder().decodeBytes(bytes);
    var fileCount = 0;
    final totalEntries = archive.files.length;

    for (final file in archive.files) {
      fileCount++;

      // Skip directories and macOS hidden files.
      final name = file.name;
      if (file.isFile == false ||
          name.endsWith('/') ||
          name.contains('__MACOSX') ||
          name.startsWith('.')) {
        continue;
      }

      // Extract just the filename (strip any path prefix).
      final fileName = name.split('/').last;
      final outFile = File('${targetDir.path}/front/$fileName');
      await outFile.parent.create(recursive: true);
      final content = file.content as List<int>;
      if (content.isEmpty) continue;
      await outFile.writeAsBytes(content);

      final p = 0.1 + (fileCount / totalEntries) * 0.85;
      onProgress?.call(p.clamp(0.1, 0.95), 'Extracting $fileName…');
    }

    // Write a marker so we don't extract again.
    final marker = File('${targetDir.path}/.ready_$_version');
    await marker.writeAsString('done');

    onProgress?.call(1.0, 'Sprites ready');
  }

  /// Returns the path prefix for front sprites on device storage.
  Future<String> get frontPath async {
    final dir = await _targetDirectory;
    return '${dir.path}/front';
  }
}
