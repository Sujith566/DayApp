import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const backupMaxFileBytes = 64 * 1024 * 1024;
const backupMaxPlainBytes = 40 * 1024 * 1024;
const _iterations = 600000;
const _aad = 'daynest-backup/v1/PBKDF2-SHA256/600000/AES-256-GCM';
List<int> _random(int length) {
  final r = Random.secure();
  return List.generate(length, (_) => r.nextInt(256));
}

Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: _iterations,
  bits: 256,
).deriveKeyFromPassword(password: password, nonce: salt);
void validateBackupPassword(String password) {
  if (password.length < 10 || utf8.encode(password).length > 512) {
    throw const FormatException(
      'Use a backup password of at least 10 characters and no more than 512 UTF-8 bytes.',
    );
  }
}

/// Top-level entry point for Flutter compute; passwords are not written to disk.
Future<Uint8List> encryptBackup(Map<String, Object?> input) async {
  final password = input['password'] as String;
  validateBackupPassword(password);
  final clear = input['bytes'] as List<int>;
  if (clear.length > backupMaxPlainBytes) {
    throw const FormatException('Backup data exceeds the 40 MB limit.');
  }
  final salt = _random(16), nonce = _random(12);
  final box = await AesGcm.with256bits().encrypt(
    clear,
    secretKey: await _key(password, salt),
    nonce: nonce,
    aad: utf8.encode(_aad),
  );
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'magic': 'DAYNEST_BACKUP',
        'version': 1,
        'kdf': 'PBKDF2-SHA256',
        'iterations': _iterations,
        'cipher': 'AES-256-GCM',
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'tag': base64Encode(box.mac.bytes),
      }),
    ),
  );
}

Future<Uint8List> decryptBackup(Map<String, Object?> input) async {
  final bytes = input['bytes'] as List<int>,
      password = input['password'] as String;
  if (bytes.length > backupMaxFileBytes) {
    throw const FormatException('Backup file exceeds the 64 MB limit.');
  }
  final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  if (data['magic'] != 'DAYNEST_BACKUP' ||
      data['version'] != 1 ||
      data['kdf'] != 'PBKDF2-SHA256' ||
      data['iterations'] != _iterations ||
      data['cipher'] != 'AES-256-GCM') {
    throw const FormatException('This is not a supported Daynest backup.');
  }
  final salt = base64Decode(data['salt'] as String),
      nonce = base64Decode(data['nonce'] as String),
      tag = base64Decode(data['tag'] as String);
  final cipher = base64Decode(data['ciphertext'] as String);
  if (salt.length != 16 ||
      nonce.length != 12 ||
      tag.length != 16 ||
      cipher.length > backupMaxPlainBytes) {
    throw const FormatException('Invalid backup envelope.');
  }
  final clear = await AesGcm.with256bits().decrypt(
    SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
    secretKey: await _key(password, salt),
    aad: utf8.encode(_aad),
  );
  return Uint8List.fromList(clear);
}
