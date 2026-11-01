import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:daynest/features/backup/backup_crypto.dart';

void main() {
  test(
    'encrypted backup round trips unicode and uses fresh randomness',
    () async {
      final clear = utf8.encode('Private journal • ₹500 • 🌿');
      final first = await encryptBackup({
        'password': 'my backup password 123',
        'bytes': clear,
      });
      final second = await encryptBackup({
        'password': 'my backup password 123',
        'bytes': clear,
      });
      expect(first, isNot(orderedEquals(second)));
      expect(
        utf8.decode(
          await decryptBackup({
            'password': 'my backup password 123',
            'bytes': first,
          }),
        ),
        utf8.decode(clear),
      );
      expect(utf8.decode(first).contains('Private journal'), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('wrong password and modified ciphertext cannot decrypt', () async {
    final encrypted = await encryptBackup({
      'password': 'my backup password 123',
      'bytes': utf8.encode('private'),
    });
    await expectLater(
      decryptBackup({'password': 'wrong password', 'bytes': encrypted}),
      throwsA(anything),
    );
    final data = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
    final cipher = base64Decode(data['ciphertext'] as String);
    cipher[0] ^= 1;
    data['ciphertext'] = base64Encode(cipher);
    await expectLater(
      decryptBackup({
        'password': 'my backup password 123',
        'bytes': utf8.encode(jsonEncode(data)),
      }),
      throwsA(anything),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('unknown version or attacker-selected KDF cost is rejected before derivation', () async {
    for (final value in [2, 1000000000]) {
      final bytes = utf8.encode(
        jsonEncode({
          'magic': 'DAYNEST_BACKUP',
          'version': value,
          'iterations': value,
        }),
      );
      await expectLater(
        decryptBackup({'password': 'anything', 'bytes': bytes}),
        throwsFormatException,
      );
    }
  });
  test('short backup passwords are rejected', () {
    expect(() => validateBackupPassword('short'), throwsFormatException);
  });
}
