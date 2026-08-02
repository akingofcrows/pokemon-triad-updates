import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Checks a remote server for app updates, downloads and installs new APKs.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static final _channel = const MethodChannel('com.xmusa.pokemon_triad/update');
  static const _apiUrl = 'https://api.github.com/repos/akingofcrows/pokemon-triad-updates/releases/latest';

  double downloadProgress = 0;
  String status = '';
  String lastError = '';

  /// Returns true if the app can install APKs (Android 8+ permission check).
  Future<bool> canInstallApk() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallApk') ?? true;
    } catch (_) {
      return true; // assume can install on error
    }
  }

  /// Opens system settings for "Install unknown apps".
  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod('openInstallSettings');
    } catch (_) {}
  }

  /// Returns an [UpdateInfo] if a newer version is available, null otherwise.
  /// Falls back to cached version info when GitHub is unreachable.
  Future<UpdateInfo?> checkForUpdate() async {
    lastError = '';
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final response = await http
          .get(Uri.parse(_apiUrl), headers: {
            'User-Agent': 'PokemonTriad/1.0',
            'Accept': 'application/vnd.github+json',
          })
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        lastError = 'GitHub HTTP ${response.statusCode}';
        return _cachedUpdate(currentVersion);
      }

      final Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        lastError = 'Bad GitHub response';
        return _cachedUpdate(currentVersion);
      }

      final tag = data['tag_name'] as String? ?? '';
      final latestVersion = tag.startsWith('v') ? tag.substring(1) : tag;
      final body = data['body'] as String? ?? '';
      final assets = data['assets'] as List<dynamic>? ?? [];
      String apkUrl = '';
      for (final a in assets) {
        final name = (a as Map<String, dynamic>)['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String? ?? '';
          break;
        }
      }

      // Cache for offline fallback
      await _cacheVersion(latestVersion);

      debugPrint('Update check: app=$currentVersion server=$latestVersion');

      if (latestVersion.isNotEmpty && _compareVersions(latestVersion, currentVersion) > 0) {
        return UpdateInfo(version: latestVersion, apkUrl: apkUrl, changelog: body);
      } else {
        lastError = 'Up to date (v$currentVersion)';
      }
    } catch (e) {
      lastError = e.toString();
      debugPrint('Update check failed: $e');
      return _cachedUpdate(null);
    }
    return null;
  }

  Future<UpdateInfo?> _cachedUpdate(String? currentVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('latestVersion');
      if (cached != null && currentVersion != null &&
          _compareVersions(cached, currentVersion) > 0) {
        return UpdateInfo(version: cached, apkUrl: '', changelog: 'Update available (offline check)');
      }
    } catch (_) {}
    return null;
  }

  Future<void> _cacheVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('latestVersion', version);
    } catch (_) {}
  }

  /// Downloads the APK and triggers installation.
  Future<bool> downloadAndInstall(String url) async {
    downloadProgress = 0;
    status = 'Downloading update…';

    // Cache-bust the download URL
    final dlUrl = '${url}${url.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}';

    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        status = 'No external storage';
        return false;
      }
      final filePath = '${dir.path}/pokemon_triad_update.apk';
      final file = File(filePath);
      if (await file.exists()) await file.delete();

      await Dio().download(
        dlUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            downloadProgress = received / total;
            status = 'Downloading ${(downloadProgress * 100).toStringAsFixed(0)}%';
          }
        },
      );

      status = 'Installing…';
      try {
        await _channel.invokeMethod('installApk', {'path': filePath});
        return true;
      } catch (e) {
        debugPrint('Install failed: $e');
        status = 'Install failed: $e';
        return false;
      }
    } catch (e) {
      debugPrint('Download failed: $e');
      status = 'Download failed: $e';
      return false;
    }
  }

  /// Compares two semantic versions. Returns >0 if a > b.
  int _compareVersions(String a, String b) {
    // Strip any pre-release suffix like "-alpha" before comparing
    final cleanA = a.split('-').first.split('.').map(int.parse).toList();
    final cleanB = b.split('-').first.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final diff = (cleanA.length > i ? cleanA[i] : 0) -
          (cleanB.length > i ? cleanB[i] : 0);
      if (diff != 0) return diff;
    }
    return 0;
  }
}

class UpdateInfo {
  final String version;
  final String apkUrl;
  final String changelog;
  const UpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.changelog,
  });
}
