/// Phase-1 hybrid content/asset update system (see
/// pokemon_triad_update_and_asset_delivery_system.md). Off by default so the
/// existing [AssetManager] flat-sync path stays the default until this is
/// proven on a real device. Enable with:
///   flutter run --dart-define=USE_CONTENT_MANAGER=true
const bool kUseContentUpdateManager = bool.fromEnvironment(
  'USE_CONTENT_MANAGER',
  defaultValue: false,
);
