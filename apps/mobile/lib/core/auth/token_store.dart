import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the session tokens in platform secure storage
/// (Keychain / Keystore / encrypted prefs / WebCrypto-backed storage on web).
class TokenStore {
  TokenStore._();
  static final instance = TokenStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kAccess = 'dayflow.accessToken';
  static const _kRefresh = 'dayflow.refreshToken';

  String? _accessToken;

  String? get accessToken => _accessToken;

  Future<String?> readRefreshToken() => _storage.read(key: _kRefresh);

  Future<void> save({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
  }

  Future<void> restore() async {
    _accessToken = await _storage.read(key: _kAccess);
  }

  Future<void> clear() async {
    _accessToken = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }
}
