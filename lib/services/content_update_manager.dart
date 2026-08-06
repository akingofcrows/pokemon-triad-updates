import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'content_update_manifest.dart';

/// Phase-1 hybrid content/asset update system. Downloads versioned bundles
/// (see pokemon_triad_update_and_asset_delivery_system.md), verifies them by
/// SHA-256, stages + atomically activates them, and keeps a one-launch
/// rollback copy. Separate from and does not touch [AssetManager]'s flat
/// sync (gated behind `kUseContentUpdateManager`).
class ContentUpdateManager {
  ContentUpdateManager._();
  static final ContentUpdateManager instance = ContentUpdateManager._();

  /// Set by the session loader when optional bundles need downloading, and
  /// consumed by Home (which has a post-navigation context to show the
  /// non-blocking [OptionalContentSheet] from) — see
  /// pokemon_triad_update_and_asset_delivery_system.md §10.
  static List<BundleDiff>? pendingOptionalDiffs;
  static String? pendingOptionalBaseUrl;

  late String _contentDir;
  LocalBundleIndex _index = LocalBundleIndex.empty();
  bool _initialized = false;

  String get _activeDir => '$_contentDir/active';
  String get _stagingDir => '$_contentDir/staging';
  String get _backupDir => '$_contentDir/backup';
  String get _downloadsDir => '$_contentDir/downloads';
  String get _indexPath => '$_contentDir/index.json';

  /// Initialize the manager. Call once at app startup, before [diff] or
  /// [downloadAndActivate]. Also promotes the previous launch's backups to
  /// permanently deleted, since reaching this point means the app launched
  /// successfully with whatever was last activated.
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _contentDir = '${dir.path}/content';
    for (final d in [_activeDir, _stagingDir, _backupDir, _downloadsDir]) {
      await Directory(d).create(recursive: true);
    }

    final indexFile = File(_indexPath);
    if (await indexFile.exists()) {
      try {
        final json = jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
        _index = LocalBundleIndex.fromJson(json);
      } catch (e) {
        debugPrint('ContentUpdateManager: corrupt index.json, starting fresh: $e');
        _index = LocalBundleIndex.empty();
      }
    }
    _initialized = true;

    // Detect bundles that were activated but never survived to a working
    // launch (e.g. corrupted mid-extraction) and auto-restore them from
    // backup/ before that one-launch rollback window closes below.
    await _validateAndRecover();

    // The app launched fine (or was just recovered), so any backups from
    // the last activation are confirmed good — safe to reclaim the space.
    await _purgeBackups();
  }

  /// True if [dir] exists and contains at least one entry.
  Future<bool> _isNonEmptyDir(Directory dir) async {
    if (!await dir.exists()) return false;
    await for (final _ in dir.list()) {
      return true;
    }
    return false;
  }

  /// Basic activation-integrity check (spec §17 "Rollback"): every bundle
  /// the index thinks is active should actually have files on disk. If one
  /// is missing or empty, roll back to the previous version kept in
  /// backup/; if there's no backup either, drop it from the index so the
  /// next [diff] treats it as needing a fresh download.
  Future<void> _validateAndRecover() async {
    for (final id in _index.bundles.keys.toList()) {
      final dir = Directory('$_activeDir/$id');
      if (await _isNonEmptyDir(dir)) continue;
      debugPrint('ContentUpdateManager: $id failed validation, attempting rollback');
      final restored = await rollback(id);
      if (!restored) {
        debugPrint('ContentUpdateManager: $id has no backup to restore; clearing from index');
        _index.bundles.remove(id);
        await _saveIndex();
      }
    }
  }

  Future<void> _purgeBackups() async {
    final dir = Directory(_backupDir);
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      try {
        await entry.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// True if [installedAppVersion] meets [manifest.minimumAppVersion]
  /// (spec §13 "Compatibility Rules"). Callers should skip content-bundle
  /// processing entirely when this is false — an app that old may not
  /// understand the new data shape — and prompt an app update instead.
  bool appVersionSupported(String installedAppVersion, ContentManifest manifest) {
    return _compareSemver(installedAppVersion, manifest.minimumAppVersion) >= 0;
  }

  Future<void> _saveIndex() async {
    await File(_indexPath).writeAsString(jsonEncode(_index.toJson()));
  }

  /// Fetch the server's content manifest. Returns null on any failure
  /// (offline, server error, malformed response) so callers can fall back
  /// to "no updates available" rather than crash.
  Future<ContentManifest?> fetchManifest({required String baseUrl}) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/content/manifest'),
            headers: {'ngrok-skip-browser-warning': 'true'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return ContentManifest.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('ContentUpdateManager: fetchManifest failed: $e');
      return null;
    }
  }

  /// Compares the server manifest against the local index. One [BundleDiff]
  /// per server-advertised bundle; check [BundleDiff.isChanged] to see which
  /// actually need downloading.
  List<BundleDiff> diff(ContentManifest server) {
    assert(_initialized, 'Call init() before diff().');
    return server.bundles
        .map((b) => BundleDiff(remote: b, local: _index.bundles[b.id]))
        .toList();
  }

  /// True if there's an interrupted download that can be resumed for
  /// [bundleId] (or any bundle, if null). The actual resume happens
  /// automatically the next time [downloadAndActivate] is called for that
  /// bundle — this is just a check callers can use to decide whether to.
  Future<bool> resumePending({String? bundleId}) async {
    final dir = Directory(_downloadsDir);
    if (!await dir.exists()) return false;
    await for (final entry in dir.list()) {
      if (entry is File && entry.path.endsWith('.meta.json')) {
        if (bundleId == null) return true;
        final name = entry.uri.pathSegments.last;
        if (name == '$bundleId.meta.json') return true;
      }
    }
    return false;
  }

  /// Downloads, verifies, extracts, and atomically activates [diff.remote].
  /// Emits progress; the final event is either [DownloadStage.done] or
  /// [DownloadStage.failed]. Resumes an interrupted download automatically
  /// if a matching partial download is found.
  Stream<DownloadProgress> downloadAndActivate(
    BundleDiff diff, {
    required String baseUrl,
  }) async* {
    final remote = diff.remote;
    final id = remote.id;
    final partFile = File('$_downloadsDir/$id.part');
    final metaFile = File('$_downloadsDir/$id.meta.json');

    yield DownloadProgress(bundleId: id, stage: DownloadStage.downloading, totalBytes: remote.sizeBytes);

    // Resume support: only trust an existing partial if it matches this
    // exact bundle version + hash target; otherwise start over.
    int startByte = 0;
    if (await partFile.exists() && await metaFile.exists()) {
      try {
        final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        if (meta['version'] == remote.version && meta['sha256'] == remote.sha256) {
          startByte = await partFile.length();
        } else {
          await partFile.delete();
        }
      } catch (_) {
        if (await partFile.exists()) await partFile.delete();
      }
    }
    await metaFile.writeAsString(jsonEncode({
      'bundleId': id,
      'version': remote.version,
      'sha256': remote.sha256,
      'sizeBytes': remote.sizeBytes,
    }));

    try {
      final dio = Dio();
      final url = '$baseUrl${remote.url}';
      final sink = partFile.openWrite(mode: startByte > 0 ? FileMode.append : FileMode.write);
      var received = startByte;
      try {
        final response = await dio.get<ResponseBody>(
          url,
          options: Options(
            responseType: ResponseType.stream,
            headers: startByte > 0 ? {'range': 'bytes=$startByte-'} : null,
          ),
        );
        await for (final chunk in response.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          yield DownloadProgress(
            bundleId: id,
            stage: DownloadStage.downloading,
            bytesReceived: received,
            totalBytes: remote.sizeBytes,
          );
        }
      } finally {
        await sink.close();
      }

      yield DownloadProgress(bundleId: id, stage: DownloadStage.verifying, totalBytes: remote.sizeBytes);
      final bytes = await partFile.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      if (digest != remote.sha256) {
        await partFile.delete();
        await metaFile.delete();
        yield DownloadProgress(
          bundleId: id,
          stage: DownloadStage.failed,
          error: 'Downloaded file failed verification',
        );
        return;
      }

      yield DownloadProgress(bundleId: id, stage: DownloadStage.extracting, totalBytes: remote.sizeBytes);
      final stagingPath = '$_stagingDir/${id}_v${remote.version}';
      final stagingDirObj = Directory(stagingPath);
      if (await stagingDirObj.exists()) await stagingDirObj.delete(recursive: true);
      await stagingDirObj.create(recursive: true);

      final archive = ZipDecoder().decodeBytes(bytes);
      var extractedCount = 0;
      for (final file in archive.files) {
        final name = file.name;
        if (!file.isFile || name.contains('__MACOSX') || name.split('/').last.startsWith('.')) {
          continue;
        }
        final outFile = File('$stagingPath/$name');
        await outFile.parent.create(recursive: true);
        final content = file.content as List<int>;
        await outFile.writeAsBytes(content);
        extractedCount++;
      }
      if (extractedCount == 0) {
        await stagingDirObj.delete(recursive: true);
        yield DownloadProgress(bundleId: id, stage: DownloadStage.failed, error: 'Bundle contained no files');
        return;
      }

      yield DownloadProgress(bundleId: id, stage: DownloadStage.activating, totalBytes: remote.sizeBytes);
      final activePath = '$_activeDir/$id';
      final activeDirObj = Directory(activePath);
      if (await activeDirObj.exists()) {
        final backupPath = '$_backupDir/${id}_old';
        final backupDirObj = Directory(backupPath);
        if (await backupDirObj.exists()) await backupDirObj.delete(recursive: true);
        // Preserve what the backup *was* so rollback() can restore the index too.
        final prevEntry = _index.bundles[id];
        if (prevEntry != null) {
          await File('$backupPath.json').create(recursive: true);
          await File('$backupPath.json').writeAsString(jsonEncode(prevEntry.toJson()));
        }
        await activeDirObj.rename(backupPath);
      }
      await stagingDirObj.rename(activePath);

      _index.bundles[id] = LocalBundleEntry(
        id: id,
        version: remote.version,
        sha256: remote.sha256,
        isRequired: remote.required,
      );
      await _saveIndex();

      await partFile.delete();
      await metaFile.delete();

      yield DownloadProgress(bundleId: id, stage: DownloadStage.done, totalBytes: remote.sizeBytes);
    } catch (e) {
      debugPrint('ContentUpdateManager: downloadAndActivate($id) failed: $e');
      yield DownloadProgress(bundleId: id, stage: DownloadStage.failed, error: e.toString());
    }
  }

  /// Restores [bundleId] to the version kept in `backup/` (only available
  /// for the one launch after an activation — see [init]'s purge step).
  Future<bool> rollback(String bundleId) async {
    final backupPath = '$_backupDir/${bundleId}_old';
    final backupMeta = File('$backupPath.json');
    final backupDirObj = Directory(backupPath);
    if (!await backupDirObj.exists() || !await backupMeta.exists()) return false;

    final activePath = '$_activeDir/$bundleId';
    final activeDirObj = Directory(activePath);
    if (await activeDirObj.exists()) await activeDirObj.delete(recursive: true);
    await backupDirObj.rename(activePath);

    final prevEntry = LocalBundleEntry.fromJson(
      jsonDecode(await backupMeta.readAsString()) as Map<String, dynamic>,
    );
    _index.bundles[bundleId] = prevEntry;
    await _saveIndex();
    await backupMeta.delete();
    return true;
  }

  /// Deletes all activated non-required bundles to free space. Returns the
  /// number of bundles removed.
  Future<int> clearOptionalCache() async {
    var removed = 0;
    final ids = _index.bundles.values.where((e) => !e.isRequired).map((e) => e.id).toList();
    for (final id in ids) {
      final dir = Directory('$_activeDir/$id');
      if (await dir.exists()) await dir.delete(recursive: true);
      _index.bundles.remove(id);
      removed++;
    }
    await _saveIndex();
    return removed;
  }

  /// The on-device path for a file within an activated bundle, or null if
  /// that bundle isn't active locally.
  String? localPath(String bundleId, String relativePath) {
    if (!_index.bundles.containsKey(bundleId)) return null;
    final file = File('$_activeDir/$bundleId/$relativePath');
    return file.existsSync() ? file.path : null;
  }
}

/// Compares two "X.Y.Z" (pre-release/build suffixes ignored) version
/// strings. Returns >0 if [a] > [b], <0 if [a] < [b], 0 if equal.
int _compareSemver(String a, String b) {
  List<int> parse(String v) => v.split('-').first.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parse(a), pb = parse(b);
  for (var i = 0; i < 3; i++) {
    final diff = (pa.length > i ? pa[i] : 0) - (pb.length > i ? pb[i] : 0);
    if (diff != 0) return diff;
  }
  return 0;
}
