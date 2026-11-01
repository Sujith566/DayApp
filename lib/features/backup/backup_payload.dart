import 'dart:convert';
import 'dart:typed_data';

import 'backup_schema.dart';
import 'backup_crypto.dart';

bool safeAttachmentName(String value) =>
    value.isNotEmpty &&
    value.length <= 240 &&
    value != '.' &&
    value != '..' &&
    !value.contains('/') &&
    !value.contains('\\') &&
    !value.contains(':') &&
    !value.contains('\u0000');

class BackupPayload {
  final Map<String, dynamic> data;
  final Map<String, Uint8List> files;
  const BackupPayload._(this.data, this.files);
  String get created => data['created'] as String;
  Map<String, dynamic> get databases =>
      Map<String, dynamic>.from(data['databases'] as Map);
  List<Map<String, Object?>> rows(String database, String table) =>
      ((databases[database] as Map)['tables'][table] as List)
          .map((r) => Map<String, Object?>.from(r as Map))
          .toList();
  Map<String, int> get counts => {
    'Journal entries': rows('daynest.db', 'journal_entries').length,
    'Journal drafts': rows('daynest.db', 'journal_drafts').length,
    'Tasks': rows('daynest_tasks.db', 'tasks').length,
    'Money records':
        rows('daynest_money.db', 'money_transactions').length +
        rows('daynest_money.db', 'money_people').length +
        rows('daynest_money.db', 'money_bills').length,
    'Notes': rows('daynest_more.db', 'notes').length,
    'Documents': rows('daynest_more.db', 'documents').length,
    'Vault entries': rows('daynest_more.db', 'vault_entries').length,
    'Habits': rows('daynest_progress.db', 'habits').length,
    'Goals': rows('daynest_progress.db', 'goals').length,
    'Attachment files': files.length,
  };
  static Set<String> attachmentReferences(Map<String, dynamic> databases) {
    final refs = <String>{};
    void photos(dynamic value) {
      if (value is! List) {
        throw const FormatException('Invalid journal photos.');
      }
      for (final photo in value) {
        final name = (photo as Map)['file'];
        if (name is! String || !safeAttachmentName(name)) {
          throw const FormatException('Invalid photo path.');
        }
        refs.add('journal_photos/$name');
      }
    }

    final journal = (databases['daynest.db'] as Map)['tables'] as Map;
    for (final row in journal['journal_entries'] as List) {
      photos(jsonDecode((row as Map)['photos_json'] as String));
    }
    for (final row in journal['journal_drafts'] as List) {
      final payload = jsonDecode((row as Map)['payload'] as String) as Map;
      photos(payload['photos'] ?? []);
    }
    final more = (databases['daynest_more.db'] as Map)['tables'] as Map;
    for (final row in more['documents'] as List) {
      final name = (row as Map)['file_name'];
      if (name is! String || !safeAttachmentName(name)) {
        throw const FormatException('Invalid document path.');
      }
      refs.add('daynest_documents/$name');
    }
    return refs;
  }

  factory BackupPayload.parse(List<int> clear) {
    if (clear.length > backupMaxPlainBytes) {
      throw const FormatException('Backup data is too large.');
    }
    final data = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(clear)) as Map,
    );
    if (data['format'] != 'daynest-data' ||
        data['version'] != 1 ||
        data['created'] is! String ||
        DateTime.tryParse(data['created']) == null) {
      throw const FormatException('Unsupported backup data version.');
    }
    final databases = Map<String, dynamic>.from(data['databases'] as Map);
    if (databases.length != backupSpecs.length) {
      throw const FormatException('Missing or unknown databases.');
    }
    var totalRows = 0;
    for (final spec in backupSpecs) {
      final item = Map<String, dynamic>.from(databases[spec['name']] as Map);
      if (item['version'] != spec['version']) {
        throw const FormatException(
          'This backup needs a different Daynest version.',
        );
      }
      final tables = Map<String, dynamic>.from(item['tables'] as Map),
          schema = spec['tables'] as Map;
      if (tables.length != schema.length) {
        throw const FormatException('Missing or unknown tables.');
      }
      for (final name in schema.keys) {
        final columns = (schema[name] as List).cast<String>().toSet(),
            rows = tables[name] as List;
        totalRows += rows.length;
        if (totalRows > 100000) {
          throw const FormatException('Backup exceeds 100,000 records.');
        }
        for (final raw in rows) {
          final row = Map<String, Object?>.from(raw as Map);
          if (row.length != columns.length ||
              !columns.containsAll(row.keys) ||
              row.values.any(
                (v) =>
                    v != null &&
                    v is! String &&
                    v is! int &&
                    !(v is double && v.isFinite),
              )) {
            throw const FormatException('Invalid backup record.');
          }
        }
      }
      final sequences = Map<String, dynamic>.from(item['sequences'] as Map);
      for (final e in sequences.entries) {
        if (!schema.containsKey(e.key) ||
            e.value is! int ||
            (e.value as int) < 0) {
          throw const FormatException('Invalid ID sequence.');
        }
      }
    }
    final files = <String, Uint8List>{};
    var size = 0;
    final rawFiles = Map<String, dynamic>.from(data['files'] as Map);
    if (rawFiles.length > 10000) {
      throw const FormatException('Too many attachment files.');
    }
    for (final item in rawFiles.entries) {
      final parts = item.key.split('/');
      if (parts.length != 2 ||
          !['journal_photos', 'daynest_documents'].contains(parts[0]) ||
          !safeAttachmentName(parts[1])) {
        throw const FormatException('Unsafe attachment path.');
      }
      final bytes = base64Decode(item.value as String);
      size += bytes.length;
      if (size > 25 * 1024 * 1024) {
        throw const FormatException(
          'Attachments exceed the 25 MB total limit.',
        );
      }
      files[item.key] = bytes;
    }
    final refs = attachmentReferences(databases);
    if (refs.length != files.length || !refs.every(files.containsKey)) {
      throw const FormatException('Missing or unexpected attachment files.');
    }
    final documents =
        (databases['daynest_more.db'] as Map)['tables']['documents'] as List;
    for (final raw in documents) {
      final row = raw as Map;
      final size = row['size'];
      if (size is! int ||
          size <= 0 ||
          files['daynest_documents/${row['file_name']}']!.length != size) {
        throw const FormatException(
          'An attached document does not match its recorded size.',
        );
      }
    }
    return BackupPayload._(data, files);
  }
}
