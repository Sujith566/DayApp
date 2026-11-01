import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const journalMoods = [
  'Calm',
  'Happy',
  'Grateful',
  'Tired',
  'Sad',
  'Stressed',
];

class JournalPhoto {
  final String file;
  final String caption;

  const JournalPhoto(this.file, [this.caption = '']);

  Map<String, dynamic> toJson() => {
    'file': file,
    'caption': caption,
  };

  factory JournalPhoto.fromJson(Map<String, dynamic> json) {
    return JournalPhoto(
      json['file'] as String,
      json['caption'] as String? ?? '',
    );
  }
}

class JournalEntry {
  final int? id;
  final String title;
  final String content;
  final String improvement;
  final String reflection;
  final String mood;
  final DateTime date;
  final List<String> tags;
  final List<JournalPhoto> photos;
  final String? richText;
  final String? deletedAt;
  final String updatedAt;

  JournalEntry({
    this.id,
    required this.title,
    required this.content,
    required this.improvement,
    required this.reflection,
    required this.date,
    this.mood = '',
    this.tags = const [],
    this.photos = const [],
    this.richText,
    this.deletedAt,
    this.updatedAt = '',
  });

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'content': content,
      'improvement': improvement,
      'reflection': reflection,
      'entry_date': DateTime(
        date.year,
        date.month,
        date.day,
      ).toIso8601String(),
      'mood': mood,
      'tags_json': jsonEncode(tags),
      'photos_json': jsonEncode(
        photos.map((photo) => photo.toJson()).toList(),
      ),
      'rich_text': richText,
      'deleted_at': deletedAt,
      'updated_at': updatedAt,
    };
  }

  factory JournalEntry.fromMap(Map<String, Object?> map) {
    return JournalEntry(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      improvement: map['improvement'] as String? ?? '',
      reflection: map['reflection'] as String? ?? '',
      date: DateTime.parse(map['entry_date'] as String),
      mood: map['mood'] as String? ?? '',
      tags: (jsonDecode(
        map['tags_json'] as String? ?? '[]',
      ) as List)
          .cast<String>(),
      photos: (jsonDecode(
        map['photos_json'] as String? ?? '[]',
      ) as List)
          .map(
            (item) => JournalPhoto.fromJson(
          Map<String, dynamic>.from(item as Map),
        ),
      )
          .toList(),
      richText: map['rich_text'] as String?,
      deletedAt: map['deleted_at'] as String?,
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }
}

class JournalDraft {
  final String key;
  final Map<String, dynamic> data;
  final String updatedAt;

  const JournalDraft(this.key, this.data, this.updatedAt);
}

class JournalDatabase {
  JournalDatabase._();

  static final instance = JournalDatabase._();

  Future<Database>? _database;

  Future<Database> get database => _database ??= _open();

  Future<Database> _open() async {
    try {
      return await openDatabase(
        p.join(await getDatabasesPath(), 'daynest.db'),
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE journal_entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              content TEXT NOT NULL,
              improvement TEXT NOT NULL,
              reflection TEXT NOT NULL,
              entry_date TEXT NOT NULL
            )
          ''');

          await _upgradeJournal(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _upgradeJournal(db);
          }
        },
      );
    } catch (_) {
      _database = null;
      rethrow;
    }
  }

  // Adds fields without deleting existing version-1 entries.
  static Future<void> _upgradeJournal(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE journal_entries "
          "ADD COLUMN mood TEXT NOT NULL DEFAULT ''",
    );

    await db.execute(
      "ALTER TABLE journal_entries "
          "ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]'",
    );

    await db.execute(
      "ALTER TABLE journal_entries "
          "ADD COLUMN photos_json TEXT NOT NULL DEFAULT '[]'",
    );

    await db.execute(
      'ALTER TABLE journal_entries ADD COLUMN rich_text TEXT',
    );

    await db.execute(
      'ALTER TABLE journal_entries ADD COLUMN deleted_at TEXT',
    );

    await db.execute(
      "ALTER TABLE journal_entries "
          "ADD COLUMN updated_at TEXT NOT NULL DEFAULT ''",
    );

    await db.execute('''
      CREATE TABLE journal_drafts (
        draft_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE journal_meta (
        meta_key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX journal_date_index '
          'ON journal_entries(entry_date)',
    );
  }

  Future<List<JournalEntry>> getEntries({
    bool trash = false,
  }) async {
    final db = await database;

    final rows = await db.query(
      'journal_entries',
      where: trash
          ? 'deleted_at IS NOT NULL'
          : 'deleted_at IS NULL',
      orderBy: 'entry_date DESC, id DESC',
    );

    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<JournalEntry?> getEntry(int id) async {
    final rows = await (await database).query(
      'journal_entries',
      where: 'id = ?',
      whereArgs: [id],
    );

    return rows.isEmpty
        ? null
        : JournalEntry.fromMap(rows.first);
  }

  Future<int> commit(
      JournalEntry entry,
      String draftKey,
      ) async {
    final db = await database;

    return db.transaction((txn) async {
      final values = entry.toMap();

      values['updated_at'] =
          DateTime.now().toUtc().toIso8601String();

      final int id;

      if (entry.id == null) {
        id = await txn.insert('journal_entries', values);
      } else {
        id = entry.id!;

        final changed = await txn.update(
          'journal_entries',
          values,
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [id],
        );

        if (changed != 1) {
          throw StateError('Entry no longer available');
        }
      }

      await txn.delete(
        'journal_drafts',
        where: 'draft_key = ?',
        whereArgs: [draftKey],
      );

      return id;
    });
  }

  Future<void> trash(int id) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.update(
        'journal_entries',
        {
          'deleted_at':
          DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await txn.delete(
        'journal_drafts',
        where: 'draft_key = ?',
        whereArgs: ['entry_$id'],
      );
    });
  }

  Future<void> restore(int id) async {
    await (await database).update(
      'journal_entries',
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> permanentlyDelete(int id) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(
        'journal_entries',
        where: 'id = ? AND deleted_at IS NOT NULL',
        whereArgs: [id],
      );

      await txn.delete(
        'journal_drafts',
        where: 'draft_key = ?',
        whereArgs: ['entry_$id'],
      );
    });
  }

  Future<void> saveDraft(
      String key,
      Map<String, dynamic> data,
      ) async {
    await (await database).insert(
      'journal_drafts',
      {
        'draft_key': key,
        'payload': jsonEncode(data),
        'updated_at':
        DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<JournalDraft>> drafts() async {
    final rows = await (await database).query(
      'journal_drafts',
      orderBy: 'updated_at DESC',
    );

    return rows.map((row) {
      return JournalDraft(
        row['draft_key'] as String,
        Map<String, dynamic>.from(
          jsonDecode(row['payload'] as String) as Map,
        ),
        row['updated_at'] as String,
      );
    }).toList();
  }

  Future<JournalDraft?> draft(String key) async {
    final rows = await (await database).query(
      'journal_drafts',
      where: 'draft_key = ?',
      whereArgs: [key],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;

    return JournalDraft(
      key,
      Map<String, dynamic>.from(
        jsonDecode(row['payload'] as String) as Map,
      ),
      row['updated_at'] as String,
    );
  }

  Future<void> removeDraft(String key) async {
    await (await database).delete(
      'journal_drafts',
      where: 'draft_key = ?',
      whereArgs: [key],
    );
  }

  Future<void> setPickerDraft(String? key) async {
    final db = await database;

    if (key == null) {
      await db.delete(
        'journal_meta',
        where: 'meta_key = ?',
        whereArgs: ['picker_draft'],
      );
    } else {
      await db.insert(
        'journal_meta',
        {
          'meta_key': 'picker_draft',
          'value': key,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<String?> pickerDraft() async {
    final rows = await (await database).query(
      'journal_meta',
      where: 'meta_key = ?',
      whereArgs: ['picker_draft'],
    );

    return rows.isEmpty
        ? null
        : rows.first['value'] as String;
  }
}