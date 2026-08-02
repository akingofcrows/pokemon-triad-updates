import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_profile.dart';

/// Persists the single local [PlayerProfile] as JSON in SharedPreferences.
class SaveService {
  static const _profileKey = 'player_profile_v1';

  Future<PlayerProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null) return null;
    return PlayerProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(PlayerProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
  }

  Future<bool> hasSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_profileKey);
  }
}
