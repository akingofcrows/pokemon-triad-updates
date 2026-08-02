import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// Loads and memoizes `dart:ui` [ui.Image]s from asset paths, for use by
/// CustomPainters (the Flutter-side card rendering used in Collection /
/// Deck Builder). Flame keeps its own separate image cache for the battle
/// board — both point at the same underlying asset files.
class ImageAssetCache {
  ImageAssetCache._();
  static final ImageAssetCache instance = ImageAssetCache._();

  final Map<String, ui.Image> _loaded = {};
  final Map<String, Future<ui.Image>> _loading = {};

  ui.Image? peek(String assetPath) => _loaded[assetPath];

  Future<ui.Image> load(String assetPath) {
    final cached = _loaded[assetPath];
    if (cached != null) return Future.value(cached);

    final inFlight = _loading[assetPath];
    if (inFlight != null) return inFlight;

    final future = _decode(assetPath);
    _loading[assetPath] = future;
    return future;
  }

  Future<ui.Image> _decode(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    _loaded[assetPath] = frame.image;
    _loading.remove(assetPath);
    return frame.image;
  }

  Future<void> preload(Iterable<String> assetPaths) {
    return Future.wait(assetPaths.map(load));
  }
}
