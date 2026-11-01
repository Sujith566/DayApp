import 'dart:convert';
import 'dart:io';

/// File-system transaction used only before application databases are opened.
/// Targets are supplied by application code, never read from the imported backup.
class RestoreTarget {
  final String live, staged, rollback;
  const RestoreTarget(this.live, this.staged, this.rollback);
}

Future<bool> restoreExists(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) !=
    FileSystemEntityType.notFound;
Future<void> removeRestorePath(String path) async {
  final kind = await FileSystemEntity.type(path, followLinks: false);
  if (kind == FileSystemEntityType.directory) {
    await Directory(path).delete(recursive: true);
  } else if (kind == FileSystemEntityType.link) {
    await Link(path).delete();
  } else if (kind != FileSystemEntityType.notFound) {
    await File(path).delete();
  }
}

Future<void> _move(String from, String to) async {
  await Directory(File(to).parent.path).create(recursive: true);
  final kind = await FileSystemEntity.type(from, followLinks: false);
  if (kind == FileSystemEntityType.directory) {
    await Directory(from).rename(to);
  } else if (kind == FileSystemEntityType.file) {
    await File(from).rename(to);
  } else {
    throw const FileSystemException('Restore source is unavailable or unsafe');
  }
}

Future<void> writeRestoreJson(File file, Map<String, dynamic> value) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  await temporary.rename(file.path);
}

class RestoreSwap {
  final File marker;
  final List<RestoreTarget> targets;
  const RestoreSwap(this.marker, this.targets);
  Future<Map<String, dynamic>> read() async =>
      Map<String, dynamic>.from(jsonDecode(await marker.readAsString()) as Map);
  Future<void> rollback(Map<String, dynamic> state) async {
    final present = (state['originalPresent'] as List).cast<bool>();
    if (present.length != targets.length) {
      throw const FormatException('Invalid recovery journal');
    }
    for (var i = targets.length - 1; i >= 0; i--) {
      final target = targets[i];
      if (await restoreExists(target.rollback)) {
        await removeRestorePath(target.live);
        await _move(target.rollback, target.live);
      } else if (!present[i]) {
        await removeRestorePath(target.live);
      }
    }
    // Record rollback completion before allowing cleanup, so recovery is repeatable.
    await writeRestoreJson(marker, {'phase': 'rolledBack'});
  }

  Future<void> apply() async {
    final state = <String, dynamic>{
      'phase': 'applying',
      'originalPresent': <bool>[],
    };
    for (final t in targets) {
      (state['originalPresent'] as List<bool>).add(await restoreExists(t.live));
    }
    await writeRestoreJson(marker, state);
    try {
      for (final target in targets) {
        if (await restoreExists(target.live)) {
          await _move(target.live, target.rollback);
        }
        if (await restoreExists(target.staged)) {
          await _move(target.staged, target.live);
        }
      }
      await writeRestoreJson(marker, {'phase': 'committed'});
    } catch (_) {
      await rollback(state);
      rethrow;
    }
  }
}
