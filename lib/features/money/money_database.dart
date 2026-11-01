import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// Money uses a separate database; the Journal database is untouched.
class MoneyDatabase {
  MoneyDatabase._();
  static final instance = MoneyDatabase._();
  Future<Database>? _opening;

  Future<Database> get database async {
    final pending = _opening;
    if (pending != null) return pending;
    final future = _open();
    _opening = future;
    try { return await future; } catch (_) { _opening = null; rethrow; }
  }

  Future<Database> _open() async => openDatabase(
    p.join(await getDatabasesPath(), 'daynest_money.db'), version: 2,
    onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute("ALTER TABLE money_transactions ADD COLUMN payment_method TEXT NOT NULL DEFAULT ''");
        await db.execute("ALTER TABLE money_transactions ADD COLUMN payment_source TEXT NOT NULL DEFAULT ''");
      }
    },
    onCreate: (db, version) async {
      await db.execute('''CREATE TABLE money_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= 100000000000),
        flow TEXT NOT NULL CHECK(flow IN ('income','expense')),
        category TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        payment_method TEXT NOT NULL DEFAULT '',
        payment_source TEXT NOT NULL DEFAULT ''
      )''');
      await db.execute('CREATE INDEX money_date ON money_transactions(entry_date)');
      await db.execute('''CREATE TABLE money_people (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= 100000000000),
        flow TEXT NOT NULL CHECK(flow IN ('receivable','payable')),
        entry_date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        settled INTEGER NOT NULL DEFAULT 0 CHECK(settled IN (0,1))
      )''');
      await db.execute('''CREATE TABLE money_bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= 100000000000),
        entry_date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        paid INTEGER NOT NULL DEFAULT 0 CHECK(paid IN (0,1)),
        transaction_id INTEGER UNIQUE REFERENCES money_transactions(id),
        CHECK((paid = 0 AND transaction_id IS NULL) OR
              (paid = 1 AND transaction_id IS NOT NULL))
      )''');
    },
  );

  static String day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, Object?>>> transactions(DateTime month) async {
    final db = await database;
    return db.rawQuery('''SELECT t.*, b.id AS bill_id FROM money_transactions t
      LEFT JOIN money_bills b ON b.transaction_id = t.id
      WHERE t.entry_date >= ? AND t.entry_date < ?
      ORDER BY t.entry_date DESC, t.id DESC''',
      [day(DateTime(month.year, month.month)), day(DateTime(month.year, month.month + 1))]);
  }
  Future<List<Map<String, Object?>>> people() async =>
    (await database).query('money_people', orderBy: 'settled ASC, entry_date DESC, id DESC');
  Future<List<Map<String, Object?>>> bills(DateTime month) async =>
    (await database).query('money_bills', where: 'entry_date >= ? AND entry_date < ?',
      whereArgs: [day(DateTime(month.year, month.month)), day(DateTime(month.year, month.month + 1))],
      orderBy: 'paid ASC, entry_date ASC, id ASC');

  void _validate(Map<String, Object?> data) {
    final amount = data['amount'];
    if (amount is! int || amount <= 0 || amount > 100000000000) throw ArgumentError('Invalid amount');
    if ((data['title'] as String? ?? '').trim().isEmpty) throw ArgumentError('Title required');
    final date = DateTime.parse(data['entry_date'] as String);
    if (date.year < 1900 || date.year > 2100) throw ArgumentError('Invalid date');
  }

  Future<void> save(String type, Map<String, Object?> data, {int? id}) async {
    _validate(data);
    if (type == 'transaction') {
      final method = data['payment_method'] as String? ?? '';
      final source = data['payment_source'] as String? ?? '';
      if (!['', 'UPI', 'Cash', 'Card', 'Bank', 'Other'].contains(method)) {
        throw ArgumentError('Invalid payment method');
      }
      if (source.length > 80 || (method == 'Cash' && source.isNotEmpty)) {
        throw ArgumentError('Invalid payment source');
      }
    }
    final table = _table(type);
    final db = await database;
    await db.transaction((txn) async {
      if (id != null) {
        final existing = await txn.query(table, where: 'id = ?', whereArgs: [id]);
        if (existing.isEmpty) throw StateError('Record no longer exists');
        if (type == 'bill' && existing.first['paid'] == 1) throw StateError('Reopen the bill before editing');
        if (type == 'transaction' && (await txn.query('money_bills',
          where: 'transaction_id = ?', whereArgs: [id])).isNotEmpty) {
          throw StateError('Manage this payment from Bills');
        }
        await txn.update(table, data, where: 'id = ?', whereArgs: [id]);
      } else {
        await txn.insert(table, data);
      }
    });
  }

  String _table(String type) => switch(type) {
    'transaction' => 'money_transactions', 'person' => 'money_people',
    'bill' => 'money_bills', _ => throw ArgumentError('Unknown record type'),
  };

  Future<void> settle(int id, bool settled) async {
    await (await database).update('money_people', {'settled': settled ? 1 : 0},
      where: 'id = ?', whereArgs: [id]);
  }

  // Bill state and the matching expense always commit together.
  Future<void> payBill(int id, DateTime paidOn) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('money_bills', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty || rows.first['paid'] == 1) return;
      final b = rows.first;
      final tx = await txn.insert('money_transactions', {
        'title': b['title'], 'amount': b['amount'], 'flow': 'expense',
        'category': 'Bills', 'entry_date': day(paidOn), 'note': b['note'],
      });
      await txn.update('money_bills', {'paid': 1, 'transaction_id': tx},
        where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> reopenBill(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('money_bills', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final tx = rows.first['transaction_id'];
      await txn.update('money_bills', {'paid': 0, 'transaction_id': null},
        where: 'id = ?', whereArgs: [id]);
      if (tx != null) await txn.delete('money_transactions', where: 'id = ?', whereArgs: [tx]);
    });
  }

  Future<void> delete(String type, int id) async {
    final db = await database;
    await db.transaction((txn) async {
      if (type == 'transaction') {
        await txn.update('money_bills', {'paid': 0, 'transaction_id': null},
          where: 'transaction_id = ?', whereArgs: [id]);
      }
      // Deleting a paid bill keeps its real expense in Transactions.
      await txn.delete(_table(type), where: 'id = ?', whereArgs: [id]);
    });
  }
}
