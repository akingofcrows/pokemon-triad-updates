/// One downloadable content bundle as described by the server manifest.
class BundleInfo {
  const BundleInfo({
    required this.id,
    required this.version,
    required this.required,
    required this.sizeBytes,
    required this.sha256,
    required this.url,
  });

  final String id;
  final int version;
  final bool required;
  final int sizeBytes;
  final String sha256;
  final String url;

  factory BundleInfo.fromJson(Map<String, dynamic> json) => BundleInfo(
    id: json['id'] as String,
    version: json['version'] as int,
    required: json['required'] as bool? ?? false,
    sizeBytes: json['sizeBytes'] as int? ?? 0,
    sha256: json['sha256'] as String,
    url: json['url'] as String,
  );
}

/// The full manifest returned by `GET /api/content/manifest`.
class ContentManifest {
  const ContentManifest({
    required this.manifestVersion,
    required this.contentVersion,
    required this.minimumAppVersion,
    required this.bundles,
    this.changeNotes = const [],
  });

  final int manifestVersion;
  final int contentVersion;
  final String minimumAppVersion;
  final List<BundleInfo> bundles;

  /// Short bullet points describing what changed in this content revision
  /// (spec §18 "Patch Notes"). Empty when the deploy didn't supply any.
  final List<String> changeNotes;

  factory ContentManifest.fromJson(Map<String, dynamic> json) => ContentManifest(
    manifestVersion: json['manifestVersion'] as int? ?? 1,
    contentVersion: json['contentVersion'] as int? ?? 0,
    minimumAppVersion: json['minimumAppVersion'] as String? ?? '0.0.0',
    bundles: (json['bundles'] as List<dynamic>)
        .map((b) => BundleInfo.fromJson(b as Map<String, dynamic>))
        .toList(),
    changeNotes: (json['changeNotes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
  );

  BundleInfo? bundleById(String id) {
    for (final b in bundles) {
      if (b.id == id) return b;
    }
    return null;
  }
}

/// What's currently activated on-device for one bundle.
class LocalBundleEntry {
  const LocalBundleEntry({
    required this.id,
    required this.version,
    required this.sha256,
    required this.isRequired,
  });

  final String id;
  final int version;
  final String sha256;
  final bool isRequired;

  factory LocalBundleEntry.fromJson(Map<String, dynamic> json) => LocalBundleEntry(
    id: json['id'] as String,
    version: json['version'] as int,
    sha256: json['sha256'] as String,
    isRequired: json['required'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'sha256': sha256,
    'required': isRequired,
  };
}

/// Persisted at `<AppDocs>/content/index.json` — the on-device record of
/// which bundle versions are currently active.
class LocalBundleIndex {
  LocalBundleIndex({required this.bundles});

  final Map<String, LocalBundleEntry> bundles;

  factory LocalBundleIndex.empty() => LocalBundleIndex(bundles: {});

  factory LocalBundleIndex.fromJson(Map<String, dynamic> json) {
    final raw = json['bundles'] as Map<String, dynamic>? ?? {};
    return LocalBundleIndex(
      bundles: raw.map(
        (k, v) => MapEntry(k, LocalBundleEntry.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'bundles': bundles.map((k, v) => MapEntry(k, v.toJson())),
  };
}

/// Comparison between a server-advertised bundle and what's active locally.
class BundleDiff {
  const BundleDiff({required this.remote, this.local});

  final BundleInfo remote;
  final LocalBundleEntry? local;

  bool get isChanged => local == null || local!.version != remote.version || local!.sha256 != remote.sha256;
  bool get isRequired => remote.required;
}

enum DownloadStage { downloading, verifying, extracting, activating, done, failed }

class DownloadProgress {
  const DownloadProgress({
    required this.bundleId,
    required this.stage,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.error,
  });

  final String bundleId;
  final DownloadStage stage;
  final int bytesReceived;
  final int totalBytes;
  final String? error;
}
