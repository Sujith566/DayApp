import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daynest/features/backup/backup_payload.dart';
import 'package:daynest/features/backup/backup_schema.dart';
import 'package:daynest/features/backup/restore_files.dart';

Map<String, dynamic> emptyPayload() => {
  'format': 'daynest-data',
  'version': 1,
  'created': '2026-11-01T00:00:00Z',
  'databases': {
    for (final spec in backupSpecs)
      spec['name']: {
        'version': spec['version'],
        'tables': {for (final table in (spec['tables'] as Map).keys) table: []},
        'sequences': <String, int>{},
      },
  },
  'files': <String, String>{},
};
void main() {
  test('empty valid backup includes every module', () {
    final payload = BackupPayload.parse(
      utf8.encode(jsonEncode(emptyPayload())),
    );
    expect(payload.counts['Tasks'], 0);
    expect(payload.counts['Attachment files'], 0);
  });
  test('unsafe attachment names and paths are rejected', () {
    for (final name in [
      '../escape',
      'a/b',
      'a\\b',
      'C:escape',
      '..',
      '\u0000',
    ]) {
      expect(safeAttachmentName(name), isFalse);
    }
    final value = emptyPayload();
    value['files'] = {
      'journal_photos/../escape': base64Encode([1]),
    };
    expect(
      () => BackupPayload.parse(utf8.encode(jsonEncode(value))),
      throwsFormatException,
    );
  });
  test('unknown tables and missing attachments are rejected', () {
    final value = emptyPayload();
    value['databases']['daynest.db']['tables']['unknown'] = [];
    expect(
      () => BackupPayload.parse(utf8.encode(jsonEncode(value))),
      throwsFormatException,
    );
    final second = emptyPayload();
    second['files'] = {
      'journal_photos/orphan.jpg': base64Encode([1]),
    };
    expect(
      () => BackupPayload.parse(utf8.encode(jsonEncode(second))),
      throwsFormatException,
    );
  });
  test(
    'successful swap installs new files and retains rollback originals',
    () async {
      final dir = await Directory.systemTemp.createTemp('daynest_swap_');
      try {
        final live = File('${dir.path}/live'),
            staged = File('${dir.path}/staged'),
            old = File('${dir.path}/rollback');
        await live.writeAsString('old');
        await staged.writeAsString('new');
        final marker = File('${dir.path}/state.json');
        final swap = RestoreSwap(marker, [
          RestoreTarget(live.path, staged.path, old.path),
        ]);
        await swap.apply();
        expect(await live.readAsString(), 'new');
        expect(await old.readAsString(), 'old');
        expect((await swap.read())['phase'], 'committed');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'interrupted swap rolls back both moved and previously absent targets',
    () async {
      final dir = await Directory.systemTemp.createTemp('daynest_rollback_');
      try {
        final live = File('${dir.path}/live'),
            old = File('${dir.path}/old'),
            added = File('${dir.path}/added');
        await live.writeAsString('new');
        await old.writeAsString('old');
        await added.writeAsString('new-only');
        final swap = RestoreSwap(File('${dir.path}/state.json'), [
          RestoreTarget(live.path, '${dir.path}/stage1', old.path),
          RestoreTarget(added.path, '${dir.path}/stage2', '${dir.path}/old2'),
        ]);
        final state = <String, dynamic>{
          'phase': 'applying',
          'originalPresent': [true, false],
        };
        await swap.rollback(state);
        expect(await live.readAsString(), 'old');
        expect(await added.exists(), isFalse);
        // Repeated recovery after a second interruption must not delete recovered originals.
        await swap.rollback(state);
        expect(await live.readAsString(), 'old');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('failed replacement rolls earlier moves back', () async {
    final dir = await Directory.systemTemp.createTemp('daynest_failure_');
    try {
      final live = File('${dir.path}/live'),
          old = File('${dir.path}/old'),
          stage = File('${dir.path}/stage');
      await live.writeAsString('old');
      await stage.writeAsString('new');
      // A file where a rollback parent directory is required causes a real IO failure.
      final second = File('${dir.path}/second'),
          block = File('${dir.path}/block');
      await second.writeAsString('second-old');
      await block.writeAsString('blocked');
      final swap = RestoreSwap(File('${dir.path}/state.json'), [
        RestoreTarget(live.path, stage.path, old.path),
        RestoreTarget(second.path, '${dir.path}/no-stage', '${block.path}/old'),
      ]);
      await expectLater(swap.apply(), throwsA(anything));
      expect(await live.readAsString(), 'old');
      expect(await second.readAsString(), 'second-old');
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'rollback recovers interruption after every move, including new targets',
    () async {
      for (var stop = 0; stop <= 5; stop++) {
        final dir = await Directory.systemTemp.createTemp('daynest_crash_');
        try {
          final live = [for (var i = 0; i < 3; i++) File('${dir.path}/live$i')];
          final stage = [
            for (var i = 0; i < 3; i++) File('${dir.path}/stage$i'),
          ];
          final old = [for (var i = 0; i < 3; i++) File('${dir.path}/old$i')];
          await live[0].writeAsString('original0');
          await live[2].writeAsString('original2');
          for (var i = 0; i < 3; i++) {
            await stage[i].writeAsString('replacement$i');
          }
          final moves = <Future<void> Function()>[
            () async {
              await live[0].rename(old[0].path);
            },
            () async {
              await stage[0].rename(live[0].path);
            },
            () async {
              await stage[1].rename(live[1].path);
            },
            () async {
              await live[2].rename(old[2].path);
            },
            () async {
              await stage[2].rename(live[2].path);
            },
          ];
          for (var i = 0; i < stop; i++) {
            await moves[i]();
          }
          final swap = RestoreSwap(File('${dir.path}/state.json'), [
            for (var i = 0; i < 3; i++)
              RestoreTarget(live[i].path, stage[i].path, old[i].path),
          ]);
          final state = <String, dynamic>{
            'phase': 'applying',
            'originalPresent': [true, false, true],
          };
          await swap.rollback(state);
          await swap.rollback(state);
          expect(await live[0].readAsString(), 'original0');
          expect(await live[1].exists(), isFalse);
          expect(await live[2].readAsString(), 'original2');
        } finally {
          await dir.delete(recursive: true);
        }
      }
    },
  );
  test('attachment-directory swap can be rolled back', () async {
    final dir = await Directory.systemTemp.createTemp('daynest_photo_swap_');
    try {
      final live = Directory('${dir.path}/photos'),
          stage = Directory('${dir.path}/stage'),
          old = Directory('${dir.path}/old');
      await live.create();
      await stage.create();
      await File('${live.path}/photo.jpg').writeAsString('original');
      await File('${stage.path}/photo.jpg').writeAsString('replacement');
      final swap = RestoreSwap(File('${dir.path}/state.json'), [
        RestoreTarget(live.path, stage.path, old.path),
      ]);
      await swap.apply();
      expect(
        await File('${live.path}/photo.jpg').readAsString(),
        'replacement',
      );
      await swap.rollback({
        'phase': 'applying',
        'originalPresent': [true],
      });
      expect(await File('${live.path}/photo.jpg').readAsString(), 'original');
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('document bytes must match recorded file size', () {
    final value = emptyPayload();
    final row = <String, dynamic>{
      for (final column
          in (backupSpecs.firstWhere(
                (s) => s['name'] == 'daynest_more.db',
              )['tables']['documents']
              as List))
        column as String: null,
    };
    row['file_name'] = 'doc.pdf';
    row['size'] = 20;
    value['databases']['daynest_more.db']['tables']['documents'] = [row];
    value['files'] = {
      'daynest_documents/doc.pdf': base64Encode([1, 2, 3]),
    };
    expect(
      () => BackupPayload.parse(utf8.encode(jsonEncode(value))),
      throwsFormatException,
    );
    row['size'] = 3;
    expect(
      BackupPayload.parse(utf8.encode(jsonEncode(value))).counts['Documents'],
      1,
    );
  });
}
