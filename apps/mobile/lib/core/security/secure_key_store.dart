import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Securely stores the user's own API key for On-device (BYO-key) mode.
///
/// Backed by the platform keystore (Android EncryptedSharedPreferences / iOS
/// Keychain) via flutter_secure_storage — never in plain SharedPreferences.
class SecureKeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  static const String _openAiKey = 'secure.openaiApiKey';

  Future<String?> readOpenAiKey() => _storage.read(key: _openAiKey);

  Future<bool> hasOpenAiKey() async {
    final value = await readOpenAiKey();
    return value != null && value.trim().isNotEmpty;
  }

  /// Writes [value] (trimmed); an empty value deletes the stored key.
  Future<void> writeOpenAiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _openAiKey);
    } else {
      await _storage.write(key: _openAiKey, value: trimmed);
    }
  }

  Future<void> clearOpenAiKey() => _storage.delete(key: _openAiKey);
}
