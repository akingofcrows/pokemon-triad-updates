import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

/// Owns the auth token (secure storage) and calls the TTMMO API's
/// register/login endpoints, storing the resulting token on success.
/// Falls back to local auth if the server is unreachable.
class AuthService {
  AuthService(this._apiClient);

  static const _tokenKey = 'auth_token';
  static const _localUsersKey = 'local_users';

  final ApiClient _apiClient;
  final _storage = const FlutterSecureStorage();

  Future<bool> get isLoggedIn async => (await currentToken) != null;

  Future<String?> get currentToken => _storage.read(key: _tokenKey);

  Future<void> register(String username, String password) async {
    try {
      final result = await _apiClient.register(username, password);
      await _storage.write(key: _tokenKey, value: result['token'] as String);
    } on ApiNetworkException {
      // Server unreachable — register locally
      await _registerLocal(username, password);
      await _storage.write(key: _tokenKey, value: 'local_${base64Encode(utf8.encode('$username:$password'))}');
    }
  }

  Future<void> login(String username, String password) async {
    try {
      final result = await _apiClient.login(username, password);
      await _storage.write(key: _tokenKey, value: result['token'] as String);
    } on ApiNetworkException {
      // Server unreachable — check local
      final users = await _getLocalUsers();
      if (users[username] != password) throw ApiException(401, 'Invalid username or password.');
      await _storage.write(key: _tokenKey, value: 'local_${base64Encode(utf8.encode('$username:$password'))}');
    }
  }

  Future<void> logout() => _storage.delete(key: _tokenKey);

  Future<Map<String, String>> _getLocalUsers() async {
    final raw = await _storage.read(key: _localUsersKey);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  Future<void> _registerLocal(String username, String password) async {
    final users = await _getLocalUsers();
    if (users.containsKey(username)) throw ApiException(409, 'Username already taken.');
    users[username] = password;
    await _storage.write(key: _localUsersKey, value: jsonEncode(users));
  }
}
