import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../journal/journal_database.dart';
import '../money/money_database.dart';
import '../tasks/tasks_database.dart';
import 'progress_model.dart';

class ProgressSnapshot {
  final List<ProgressRow> habits, goals;
  final Set<String> logs;
  const ProgressSnapshot(this.habits, this.goals, this.logs);
  List<ProgressRow> active(DateTime now) => habits.where((h) => habitEligible(h, progressDay(now))).toList();
}
class ProgressStore {
  ProgressStore._();
  static final instance = ProgressStore._();
  final revision = ValueNotifier<int>(0);
  Future<Database>? _opening;
  Future<Database> get database async {
    if (_opening != null) { return _opening!; }
    final future = _open(); _opening = future;
    try { return await future; } catch (_) { _opening = null; rethrow; }
  }
  Future<Database> _open() async => openDatabase(p.join(await getDatabasesPath(), 'daynest_progress.db'), version: 1,
    onConfigure: (db) async { await db.execute('PRAGMA foreign_keys = ON'); },
    onCreate: (db, v) async {
      await db.execute('''CREATE TABLE habits(id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,category TEXT NOT NULL CHECK(category IN ('Mind','Body','Growth')),
        created_on TEXT NOT NULL,archived_on TEXT)''');
      await db.execute('''CREATE TABLE habit_logs(habit_id INTEGER NOT NULL REFERENCES habits(id),
        day TEXT NOT NULL,PRIMARY KEY(habit_id,day))''');
      await db.execute('''CREATE TABLE goals(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,
        unit TEXT NOT NULL,target REAL NOT NULL CHECK(target>0),current REAL NOT NULL DEFAULT 0 CHECK(current>=0),
        period TEXT NOT NULL,start_on TEXT NOT NULL,end_on TEXT NOT NULL)''');
    });
  void changed() { revision.value++; }
  Future<ProgressSnapshot> snapshot() async {
    final db = await database;
    return db.transaction((txn) async => ProgressSnapshot(
      await txn.query('habits', orderBy: 'id'), await txn.query('goals', orderBy: 'end_on,id'),
      (await txn.query('habit_logs')).map((r) => logKey(r['habit_id'] as int, r['day'] as String)).toSet()));
  }
  Future<void> addHabit(String title, String category) async {
    if (title.trim().isEmpty || title.trim().length > 100 || !['Mind','Body','Growth'].contains(category)) {
      throw ArgumentError('Use a name of 1–100 characters and choose a category.');
    }
    await (await database).insert('habits', {'title':title.trim(), 'category':category, 'created_on':progressDay(DateTime.now())});
    changed();
  }
  Future<void> archive(int id) async {
    // Preserve today's eligibility and all past history; stop scheduling tomorrow.
    await (await database).update('habits', {'archived_on':progressDay(shiftDay(DateTime.now(), 1))},
      where:'id = ? AND archived_on IS NULL', whereArgs:[id]);
    changed();
  }
  Future<void> deleteHabit(int id) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(
        'habit_logs',
        where: 'habit_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'habits',
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    changed();
  }
  Future<void> checkHabit(int id, DateTime date, bool done) async {
    final day = progressDay(date), today = progressDay(DateTime.now());
    if (day.compareTo(today)>0) { throw ArgumentError('Future days cannot be checked.'); }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('habits', where:'id = ?', whereArgs:[id]);
      if (rows.isEmpty || !habitEligible(rows.first, day)) { throw StateError('Habit is not scheduled on this date.'); }
      if (done) {
        await txn.insert('habit_logs', {'habit_id':id,'day':day}, conflictAlgorithm:ConflictAlgorithm.ignore);
      } else { await txn.delete('habit_logs', where:'habit_id = ? AND day = ?', whereArgs:[id,day]); }
    });
    changed();
  }
  Future<void> saveGoal({int? id, required String title, required String unit, required double target,
    required double current, required String period}) async {
    if (title.trim().isEmpty || title.length>100 || unit.trim().isEmpty || unit.length>30 || !target.isFinite ||
      !current.isFinite || target<=0 || target>1e9 || current<0 || current>1e9 || !['Quarterly','Annual'].contains(period)) {
      throw ArgumentError('Check the goal name, unit, and progress values.');
    }
    final now = DateTime.now();
    final start = period=='Annual' ? DateTime(now.year) : DateTime(now.year, ((now.month-1)~/3)*3+1);
    final end = period=='Annual' ? DateTime(now.year+1,1,0) : DateTime(start.year,start.month+3,0);
    final values = <String,Object?>{'title':title.trim(),'unit':unit.trim(),'target':target,'current':current,'period':period};
    final db = await database;
    if (id==null) {
      await db.insert('goals', {...values,'start_on':progressDay(start),'end_on':progressDay(end)});
    } else {
      // Updating an existing goal keeps its original period dates.
      await db.update('goals', values, where:'id = ?', whereArgs:[id]);
    }
    changed();
  }
  Future<void> deleteGoal(int id) async {
    await (await database).delete('goals', where:'id = ?', whereArgs:[id]); changed();
  }
  Future<ReviewSummary> review(ProgressSnapshot snapshot, int count, DateTime now) async {
    final days = reviewDays(now, count), start = progressDay(shiftDay(now, 1-count)), end = progressDay(now);
    final tasks = await TasksDatabase.instance.database;
    final journal = await JournalDatabase.instance.database;
    final money = await MoneyDatabase.instance.database;
    final taskRows = await tasks.rawQuery('''SELECT count(*) AS n FROM tasks WHERE deleted=0 AND done=1
      AND completed_at IS NOT NULL AND substr(completed_at,1,10) BETWEEN ? AND ?''', [start,end]);
    final unknown = await tasks.rawQuery('SELECT count(*) AS n FROM tasks WHERE deleted=0 AND done=1 AND completed_at IS NULL');
    final journalRows = await journal.rawQuery('''SELECT count(DISTINCT substr(entry_date,1,10)) AS n FROM journal_entries
      WHERE deleted_at IS NULL AND substr(entry_date,1,10) BETWEEN ? AND ?''', [start,end]);
    final spend = await money.rawQuery('''SELECT coalesce(sum(amount),0) AS n FROM money_transactions
      WHERE flow='expense' AND entry_date BETWEEN ? AND ?''', [start,end]);
    return ReviewSummary(days:count, finished:taskRows.first['n'] as int,
      journalDays:journalRows.first['n'] as int, spending:spend.first['n'] as int,
      unknownCompletions:unknown.first['n'] as int, habits:HabitScore.calculate(snapshot.habits,snapshot.logs,days));
  }
}
