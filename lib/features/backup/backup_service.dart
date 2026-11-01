import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../journal/journal_database.dart';
import '../money/money_database.dart';
import '../more/more_store.dart';
import '../more/vault_store.dart';
import '../progress/progress_store.dart';
import '../tasks/tasks_database.dart';
import '../tasks/task_reminders.dart';
import 'backup_crypto.dart';
import 'backup_payload.dart';
import 'backup_schema.dart';
import 'restore_files.dart';
import 'dart:typed_data';

class BackupService {
  BackupService._();
  static final instance = BackupService._();
  final restartRequired = ValueNotifier<bool>(false);
  bool _busy = false;
  Future<String?>? _starting;
  bool _cancelling = false;
  Future<Directory> _root() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'daynest_backup'),
  ).create(recursive: true);
  Future<Directory> _work() async =>
      Directory(p.join((await _root()).path, 'restore_work'));
  Future<File> _statusFile() async =>
      File(p.join((await _root()).path, 'status.json'));
  Future<Map<String, dynamic>> status() async {
    final file = await _statusFile();
    if (!await file.exists()) {
      return {};
    }
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  Future<void> _status(Map<String, dynamic> changes) async {
    await writeRestoreJson(await _statusFile(), {
      ...await status(),
      ...changes,
    });
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy || restartRequired.value) {
      throw StateError('Another backup or restore is already in progress.');
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, Database>> _databases() async => {
    'daynest.db': await JournalDatabase.instance.database,
    'daynest_money.db': await MoneyDatabase.instance.database,
    'daynest_tasks.db': await TasksDatabase.instance.database,
    'daynest_more.db': await MoreStore.instance.db,
    'daynest_progress.db': await ProgressStore.instance.database,
  };
  Future<Uint8List> _snapshot() async {
    final databases = <String, dynamic>{}, opened = await _databases();
    for (final spec in backupSpecs) {
      final db = opened[spec['name']]!;
      if (await db.getVersion() != spec['version']) {
        throw const FormatException(
          'Database version does not match this backup module.',
        );
      }
      databases[spec['name']] = await db.transaction((txn) async {
        final tables = <String, dynamic>{};
        for (final table in (spec['tables'] as Map).keys.cast<String>()) {
          final columns = (await txn.rawQuery('PRAGMA table_info("$table")'))
              .map((r) => r['name'])
              .toSet();
          if (!setEquals(columns, (spec['tables'][table] as List).toSet())) {
            throw const FormatException(
              'Database structure is newer or different.',
            );
          }
          tables[table] = await txn.query(table);
        }
        final sequences = <String, int>{};
        for (final row in await txn.query('sqlite_sequence')) {
          if ((spec['tables'] as Map).containsKey(row['name'])) {
            sequences[row['name'] as String] = row['seq'] as int;
          }
        }
        return {
          'version': spec['version'],
          'tables': tables,
          'sequences': sequences,
        };
      });
    }
    final files = <String, String>{},
        docs = (await getApplicationDocumentsDirectory()).path;
    var total = 0;
    for (final name in BackupPayload.attachmentReferences(databases)) {
      final file = File(p.joinAll([docs, ...name.split('/')]));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FileSystemException(
          'An attached photo or document is missing. A complete backup cannot be created.',
        );
      }
      total += await file.length();
      if (total > 25 * 1024 * 1024) {
        throw const FormatException(
          'This version supports up to 25 MB of attachments in total.',
        );
      }
      files[name] = base64Encode(await file.readAsBytes());
    }
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'daynest-data',
          'version': 1,
          'created': DateTime.now().toUtc().toIso8601String(),
          'databases': databases,
          'files': files,
        }),
      ),
    );
    // The same strict validation is applied to exports and imports.
    BackupPayload.parse(bytes);
    return bytes;
  }

  Future<Uint8List> create(String password) => _exclusive(() async {
    validateBackupPassword(password);
    VaultStore.instance.lock();
    return compute(encryptBackup, <String, Object?>{
      'password': password,
      'bytes': await _snapshot(),
    });
  });
  Future<void> recordExport() =>
      _status({'lastExport': DateTime.now().toUtc().toIso8601String()});
  Future<BackupPayload> inspect(Uint8List bytes, String password) =>
      _exclusive(() async {
        final clear = await compute(decryptBackup, <String, Object?>{
          'bytes': bytes,
          'password': password,
        });
        final payload = BackupPayload.parse(clear);
        await _stage(payload);
        return payload;
      });
  Future<void> discardPreview() async {
    final work = await _work();
    final marker = File(p.join(work.path, 'state.json'));
    if (await marker.exists()) {
      return;
    }
    if (await work.exists()) {
      await work.delete(recursive: true);
    }
  }

  Future<void> _stage(BackupPayload payload) async {
    final work = await _work();
    if (await File(p.join(work.path, 'state.json')).exists()) {
      throw StateError('A restore is already awaiting restart.');
    }
    if (await work.exists()) {
      await work.delete(recursive: true);
    }
    final stage = Directory(p.join(work.path, 'stage'));
    await stage.create(recursive: true);
    try {
      for (final spec in backupSpecs) {
        final path = p.join(stage.path, 'db', spec['name'] as String);
        await Directory(p.dirname(path)).create(recursive: true);
        final db = await openDatabase(
          path,
          version: spec['version'] as int,
          singleInstance: false,
          onConfigure: (db) async {
            await db.execute('PRAGMA journal_mode=DELETE');
            await db.execute('PRAGMA foreign_keys=ON');
          },
          onCreate: (db, _) async {
            for (final sql in spec['create'] as List) {
              await db.execute(sql as String);
            }
          },
        );
        try {
          await db.transaction((txn) async {
            for (final table in (spec['tables'] as Map).keys.cast<String>()) {
              for (final row in payload.rows(spec['name'] as String, table)) {
                await txn.insert(table, row);
              }
            }
            final sequences =
                (payload.databases[spec['name']] as Map)['sequences'] as Map;
            for (final entry in sequences.entries) {
              final rows = await txn.query(
                'sqlite_sequence',
                where: 'name = ?',
                whereArgs: [entry.key],
              );
              final old = rows.isEmpty ? 0 : rows.first['seq'] as int;
              if (rows.isEmpty) {
                await txn.insert('sqlite_sequence', {
                  'name': entry.key,
                  'seq': entry.value,
                });
              } else if ((entry.value as int) > old) {
                await txn.update(
                  'sqlite_sequence',
                  {'seq': entry.value},
                  where: 'name = ?',
                  whereArgs: [entry.key],
                );
              }
            }
            if (spec['name'] == 'daynest_more.db') {
              await txn.insert('preferences', {
                'name': 'app_lock',
                'value': 'disabled',
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            if (spec['name'] == 'daynest.db') {
              await txn.delete(
                'journal_meta',
                where: 'meta_key = ?',
                whereArgs: ['picker_draft'],
              );
            }
            // Completion triggers are installed after import, preserving historical timestamps.
            for (final sql in spec['after'] as List) {
              await txn.execute(sql as String);
            }
            if ((await txn.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
              throw const FormatException(
                'Backup contains broken record references.',
              );
            }
          });
          final result = await db.rawQuery('PRAGMA integrity_check');
          if (result.length != 1 || result.first.values.first != 'ok') {
            throw const FormatException(
              'Restored database failed its integrity check.',
            );
          }
        } finally {
          await db.close();
        }
      }
      for (final folder in ['journal_photos', 'daynest_documents']) {
        await Directory(p.join(stage.path, 'docs', folder))
            .create(recursive: true);
      }
      for (final file in payload.files.entries) {
        await File(p.joinAll([stage.path, 'docs', ...file.key.split('/')]))
            .writeAsBytes(file.value, flush: true);
      }
    } catch (_) {
      if (await work.exists()) {
        await work.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> queueRestore(String password) => _exclusive(() async {
    final work = await _work();
    if (!await Directory(p.join(work.path, 'stage')).exists()) {
      throw StateError('Select and preview the backup again.');
    }
    // Create and durably save a full encrypted safety copy before marking the restore ready.
    final encrypted = await compute(encryptBackup, <String, Object?>{
      'bytes': await _snapshot(),
      'password': password,
    });
    final root = await _root();
    final safety = File(p.join(root.path, 'safety.daynest'));
    final temporary = File('${safety.path}.tmp');
    await temporary.writeAsBytes(encrypted, flush: true);
    await temporary.rename(safety.path);
    await _status({'safetyCreated': DateTime.now().toUtc().toIso8601String()});
    await writeRestoreJson(File(p.join(work.path, 'state.json')), {
      'phase': 'ready',
    });
    VaultStore.instance.lock();
    restartRequired.value = true;
  });
  Future<Uint8List?> safetyBytes() async {
    final file = File(p.join((await _root()).path, 'safety.daynest'));
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<List<RestoreTarget>> _targets(Directory work) async {
    final dbs = await getDatabasesPath(),
        docs = (await getApplicationDocumentsDirectory()).path;
    final result = <RestoreTarget>[];
    for (final spec in backupSpecs) {
      final name = spec['name'] as String;
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        result.add(
          RestoreTarget(
            p.join(dbs, '$name$suffix'),
            p.join(work.path, 'stage', 'db', '$name$suffix'),
            p.join(work.path, 'rollback', 'db', '$name$suffix'),
          ),
        );
      }
    }
    for (final name in ['journal_photos', 'daynest_documents']) {
      result.add(
        RestoreTarget(
          p.join(docs, name),
          p.join(work.path, 'stage', 'docs', name),
          p.join(work.path, 'rollback', 'docs', name),
        ),
      );
    }
    return result;
  }

  Future<bool> cancelPendingRestore() async {
    if (_starting != null || _cancelling) {
      return false;
    }
    _cancelling = true;
    try {
      final work = await _work(),
          marker = File(p.join((await _work()).path, 'state.json'));
      if (await marker.exists()) {
        final swap = RestoreSwap(marker, await _targets(work));
        final state = await swap.read();
        if (state['phase'] == 'committed') {
          return false;
        }
        if (state['phase'] == 'applying') {
          await swap.rollback(state);
        } else if (!['ready', 'rolledBack'].contains(state['phase'])) {
          return false;
        }
      }
      if (await work.exists()) {
        await work.delete(recursive: true);
      }
      restartRequired.value = false;
      return true;
    } finally {
      _cancelling = false;
    }
  }

  /// Call before runApp, DaynestSettings.load, or any module database getter.
  Future<String?> startup() {
    if (_cancelling) {
      return Future.value(
        'Recovery is still busy. Wait a moment, then tap Retry.',
      );
    }
    return _starting ??= _startupImpl().whenComplete(() {
      _starting = null;
    });
  }

  Future<String?> _startupImpl() async {
    try {
      final work = await _work(),
          marker = File(p.join((await _work()).path, 'state.json'));
      if (await marker.exists()) {
        final swap = RestoreSwap(marker, await _targets(work));
        final state = await swap.read();
        final phase = state['phase'];
        if (phase == 'ready') {
          // Validate presence before any live file is moved.
          for (final spec in backupSpecs) {
            final stagedPath = p.join(
              work.path,
              'stage',
              'db',
              spec['name'] as String,
            );
            if (!await File(stagedPath).exists()) {
              throw const FileSystemException('A staged database is missing.');
            }
            final check = await openDatabase(
              stagedPath,
              readOnly: true,
              singleInstance: false,
            );
            try {
              final integrity = await check.rawQuery('PRAGMA integrity_check');
              if (await check.getVersion() != spec['version'] ||
                  integrity.length != 1 ||
                  integrity.first.values.first != 'ok' ||
                  (await check.rawQuery('PRAGMA foreign_key_check'))
                      .isNotEmpty) {
                throw const FormatException(
                  'A staged database failed validation.',
                );
              }
            } finally {
              await check.close();
            }
          }
          for (final name in ['journal_photos', 'daynest_documents']) {
            if (!await Directory(p.join(work.path, 'stage', 'docs', name))
                .exists()) {
              throw const FileSystemException(
                'Staged attachments are missing.',
              );
            }
          }
          await swap.apply();
          await _status({
            'lastRestore': DateTime.now().toUtc().toIso8601String(),
            'remindersPending': true,
            'notice': 'Backup restored. Configure app lock again in Settings.',
          });
        } else if (phase == 'applying') {
          await swap.rollback(state);
          await _status({
            'notice': 'An interrupted restore was rolled back. Your previous data was recovered.',
          });
        } else if (phase == 'committed') {
          await _status({
            'lastRestore': DateTime.now().toUtc().toIso8601String(),
            'remindersPending': true,
            'notice': 'Backup restored. Configure app lock again in Settings.',
          });
        } else if (phase == 'rolledBack') {
          await _status({
            'notice': 'The restore was rolled back. Your previous data was recovered.',
          });
        } else {
          throw const FormatException('Invalid restore recovery state.');
        }
        await work.delete(recursive: true);
      } else if (await work.exists()) {
        await work.delete(recursive: true);
      }
      final saved = await status();
      if (saved['remindersPending'] == true) {
        try {
          await TaskReminders.instance.initialize();
          await FlutterLocalNotificationsPlugin().cancelAll();
          final warning = await TaskReminders.instance.sync();
          await _status({
            'remindersPending': warning != null,
            'reminderWarning': warning,
          });
        } catch (_) {
          await _status({
            'reminderWarning': 'Open Tasks → Retry reminders after restoring.',
          });
        }
      }
      restartRequired.value = false;
      return null;
    } catch (_) {
      return 'Daynest could not finish restore recovery. Your safety copy and recovery files have been kept. Free some device space, then tap Retry. Do not clear app storage.';
    }
  }
}
