import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef TaskRow = Map<String, Object?>;

String taskDay(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
List<Map<String, Object?>> taskChecklist(TaskRow row) =>
  (jsonDecode(row['checklist'] as String? ?? '[]') as List)
    .map((v) => Map<String,Object?>.from(v as Map)).toList();

class TasksDatabase {
  TasksDatabase._();
  static final instance = TasksDatabase._();
  Future<Database>? _opening;
  Future<Database> get database async {
    final current = _opening;
    if (current != null) return current;
    final future = _open(); _opening = future;
    try { return await future; } catch (_) { _opening = null; rethrow; }
  }
  Future<Database> _open() async => openDatabase(
    p.join(await getDatabasesPath(),'daynest_tasks.db'), version: 3,
    onUpgrade:(db,oldVersion,newVersion)async{
      if(oldVersion<2){
        await db.execute('ALTER TABLE tasks ADD COLUMN reminder_minutes INTEGER CHECK(reminder_minutes IS NULL OR reminder_minutes IN (0,10,60))');
      }
      if(oldVersion<3){
        await db.execute('ALTER TABLE tasks ADD COLUMN completed_at TEXT');
        await _completionTriggers(db);
      }
    },
    onCreate: (db,version) async {
      await db.execute('''CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL CHECK(length(trim(title)) > 0),
        note TEXT NOT NULL DEFAULT '',
        due_date TEXT,
        due_minutes INTEGER CHECK(due_minutes IS NULL OR due_minutes BETWEEN 0 AND 1439),
        priority TEXT NOT NULL DEFAULT 'Normal' CHECK(priority IN ('High','Normal','Low')),
        category TEXT NOT NULL DEFAULT '',
        done INTEGER NOT NULL DEFAULT 0 CHECK(done IN (0,1)),
        checklist TEXT NOT NULL DEFAULT '[]',
        deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)),
        completed_at TEXT,
        reminder_minutes INTEGER CHECK(reminder_minutes IS NULL OR reminder_minutes IN (0,10,60)),
        CHECK(due_date IS NOT NULL OR due_minutes IS NULL)
      )''');
      await db.execute('CREATE INDEX tasks_due ON tasks(deleted,done,due_date)');
      await _completionTriggers(db);
    });

  static Future<void> _completionTriggers(Database db) async {
    await db.execute("""CREATE TRIGGER tasks_completed_insert AFTER INSERT ON tasks
      WHEN NEW.done=1 BEGIN UPDATE tasks SET completed_at=strftime('%Y-%m-%dT%H:%M:%f','now','localtime') WHERE id=NEW.id; END""");
    await db.execute("""CREATE TRIGGER tasks_completed_update AFTER UPDATE OF done ON tasks
      WHEN NEW.done<>OLD.done BEGIN UPDATE tasks SET completed_at=CASE WHEN NEW.done=1
      THEN strftime('%Y-%m-%dT%H:%M:%f','now','localtime') ELSE NULL END WHERE id=NEW.id; END""");
  }

  Future<List<TaskRow>> all({bool trash=false}) async => (await database).query(
    'tasks',where:'deleted = ?',whereArgs:[trash?1:0],orderBy:'done ASC, due_date ASC, id DESC');

  Future<TaskRow?> get(int id) async {
    final rows=await (await database).query('tasks',where:'id = ? AND deleted = 0',whereArgs:[id]);
    return rows.isEmpty?null:rows.first;
  }

  Future<void> save(TaskRow data,{int? id}) async {
    final title = (data['title'] as String? ?? '').trim();
    if(title.isEmpty || title.length>160) throw ArgumentError('Invalid title');
    if(!['High','Normal','Low'].contains(data['priority'])) throw ArgumentError('Invalid priority');
    final due=data['due_date'] as String?;
    if(due!=null){
      final d=DateTime.parse(due);
      if(d.year<1900 || d.year>2100 || taskDay(d)!=due) throw ArgumentError('Invalid date');
    }
    final lead=data['reminder_minutes'];
    if(lead!=null && (!(const [0,10,60]).contains(lead) || due==null || data['due_minutes']==null)) {
      throw ArgumentError('A reminder needs a date, time, and valid lead');
    }
    final checks=taskChecklist(data);
    if(checks.length>50 || checks.any((c)=>(c['text'] as String).trim().isEmpty || c['done'] is! bool)) {
      throw ArgumentError('Invalid checklist');
    }
    final db=await database;
    if(id==null){await db.insert('tasks',data);}
    else {
      final changed=await db.update('tasks',data,where:'id = ? AND deleted = 0',whereArgs:[id]);
      if(changed!=1) throw StateError('Task unavailable');
    }
  }

  Future<void> toggle(int id,bool done) async {
    final db=await database;
    await db.transaction((txn)async{
      final rows=await txn.query('tasks',where:'id = ? AND deleted = 0',whereArgs:[id]);
      if(rows.isEmpty)throw StateError('Task unavailable');
      final checks=taskChecklist(rows.first);
      if(done){for(final c in checks){c['done']=true;}}
      await txn.update('tasks',{'done':done?1:0,'checklist':jsonEncode(checks)},where:'id = ?',whereArgs:[id]);
    });
  }

  Future<void> toggleCheck(int id,int index,bool done) async {
    final db=await database;
    await db.transaction((txn)async{
      final rows=await txn.query('tasks',where:'id = ? AND deleted = 0',whereArgs:[id]);
      if(rows.isEmpty)throw StateError('Task unavailable');
      final checks=taskChecklist(rows.first);
      if(index<0 || index>=checks.length)throw ArgumentError('Invalid checklist item');
      checks[index]['done']=done;
      await txn.update('tasks',{'checklist':jsonEncode(checks),
        'done':checks.isNotEmpty && checks.every((c)=>c['done']==true)?1:0},where:'id = ?',whereArgs:[id]);
    });
  }

  Future<void> trash(int id) async => _setDeleted(id,true);
  Future<void> restore(int id) async => _setDeleted(id,false);
  Future<void> _setDeleted(int id,bool deleted) async {
    await (await database).update('tasks',{'deleted':deleted?1:0},where:'id = ?',whereArgs:[id]);
  }
  Future<void> remove(int id) async {
    await (await database).delete('tasks',where:'id = ? AND deleted = 1',whereArgs:[id]);
  }
}
