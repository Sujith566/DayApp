import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

typedef MoreRow=Map<String,Object?>;
class MoreStore{
  MoreStore._();static final instance=MoreStore._();Future<Database>? _opening;
  Future<Database> get db async{
    if(_opening!=null)return _opening!;
    final future=_open();_opening=future;
    try{return await future;}catch(_){_opening=null;rethrow;}
  }
  Future<Database> _open()async=>openDatabase(p.join(await getDatabasesPath(),'daynest_more.db'),version:1,
    onConfigure:(db)async{await db.execute('PRAGMA foreign_keys = ON');},
    onCreate:(db,v)async{
      await db.execute('CREATE TABLE folders(id INTEGER PRIMARY KEY,kind TEXT NOT NULL,name TEXT NOT NULL,UNIQUE(kind,name))');
      await db.execute('''CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
        pinned INTEGER NOT NULL DEFAULT 0,deleted INTEGER NOT NULL DEFAULT 0,updated_at TEXT NOT NULL)''');
      await db.execute('''CREATE TABLE documents(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,
        file_name TEXT NOT NULL UNIQUE,original_name TEXT NOT NULL,size INTEGER NOT NULL,
        folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,starred INTEGER NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',expires TEXT,deleted INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL)''');
      await db.execute('CREATE TABLE preferences(name TEXT PRIMARY KEY,value TEXT NOT NULL)');
      await db.execute('CREATE TABLE vault_meta(id INTEGER PRIMARY KEY CHECK(id=1),payload TEXT NOT NULL)');
      await db.execute('CREATE TABLE vault_entries(id INTEGER PRIMARY KEY AUTOINCREMENT,payload TEXT NOT NULL)');
      for(final name in ['Business','Personal','Learning']){await db.insert('folders',{'kind':'notes','name':name});}
      for(final name in ['Government ID','Education','Certificates','Insurance']){await db.insert('folders',{'kind':'documents','name':name});}
    });
  Future<List<MoreRow>> folders(String kind)async=>(await db).query('folders',where:'kind = ?',whereArgs:[kind],orderBy:'name COLLATE NOCASE');
  Future<void> folder(String kind,String name)async{
    if(!['notes','documents'].contains(kind)||name.trim().isEmpty||name.trim().length>50)throw ArgumentError('Invalid folder');
    await (await db).insert('folders',{'kind':kind,'name':name.trim()});
  }
  Future<void> deleteFolder(int id)async{await(await db).delete('folders',where:'id = ?',whereArgs:[id]);}
  String _table(String kind){if(!['notes','documents'].contains(kind))throw ArgumentError('Invalid kind');return kind;}
  Future<List<MoreRow>> list(String kind,{bool trash=false})async=>(await db).query(_table(kind),
    where:'deleted = ?',whereArgs:[trash?1:0],orderBy:kind=='notes'?'pinned DESC,updated_at DESC,id DESC':'starred DESC,created_at DESC,id DESC');
  Future<void> saveNote(MoreRow data,{int? id})async{
    if((data['title'] as String).trim().isEmpty)throw ArgumentError('Title required');
    final values={...data,'updated_at':DateTime.now().toUtc().toIso8601String()};
    final database=await db;
    if(id==null){await database.insert('notes',values);}else{await database.update('notes',values,where:'id = ? AND deleted = 0',whereArgs:[id]);}
  }
  Future<void> update(String kind,int id,MoreRow data)async{await(await db).update(_table(kind),data,where:'id = ?',whereArgs:[id]);}
  Future<void> trash(String kind,int id,bool value)async=>update(kind,id,{'deleted':value?1:0});
  Future<bool> remove(String kind,MoreRow row)async{
    final changed=await(await db).delete(_table(kind),where:'id = ? AND deleted = 1',whereArgs:[row['id']]);
    if(changed!=1)throw StateError('Record must be in trash');
    if(kind=='documents'){
      try{final f=await documentFile(row['file_name'] as String);if(await f.exists())await f.delete();}
      catch(_){return false;}
    }
    return true;
  }
  Future<Directory> documentDirectory()async=>Directory(p.join((await getApplicationDocumentsDirectory()).path,'daynest_documents')).create(recursive:true);
  Future<File> documentFile(String name)async{
    if(p.basename(name)!=name || name.contains('..'))throw ArgumentError('Invalid file name');
    return File(p.join((await documentDirectory()).path,name));
  }
  Future<void> importDocument({required String name,required Stream<List<int>> stream,int? folderId})async{
    const limit=25*1024*1024;
    final random=Random.secure();
    final token=List.generate(16,(_)=>random.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
    final ext=p.extension(name).toLowerCase();
    final safeExt=RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(ext)?ext:'';
    final file=await documentFile('$token$safeExt');
    var count=0;final sink=file.openWrite();
    try{
      await for(final bytes in stream){count+=bytes.length;if(count>limit)throw StateError('Use a file under 25 MB');sink.add(bytes);}
      await sink.flush();await sink.close();
      if(count==0)throw StateError('Empty file');
      await(await db).insert('documents',{'title':p.basenameWithoutExtension(name),'original_name':p.basename(name),
        'file_name':p.basename(file.path),'size':count,'folder_id':folderId,'created_at':DateTime.now().toUtc().toIso8601String()});
    }catch(_){try{await sink.close();if(await file.exists())await file.delete();}catch(_){}rethrow;}
  }
}
class DaynestSettings{
  static final theme=ValueNotifier<ThemeMode>(ThemeMode.system);
  static String? loadError;
  static int _epoch=0;
  static Future<void> load()async{
    final epoch=_epoch;
    try{final rows=await(await MoreStore.instance.db).query('preferences',where:'name = ?',whereArgs:['theme']);
      if(epoch!=_epoch)return;
      final value=rows.isEmpty?'system':rows.first['value'];
      theme.value=switch(value){'light'=>ThemeMode.light,'dark'=>ThemeMode.dark,_=>ThemeMode.system};loadError=null;
    }catch(_){loadError='Could not load preferences. Your current session uses the system theme.';}
  }
  static Future<void> setTheme(ThemeMode value)async{
    _epoch++;
    await(await MoreStore.instance.db).insert('preferences',{'name':'theme','value':value.name},conflictAlgorithm:ConflictAlgorithm.replace);
    theme.value=value;loadError=null;
  }
}
