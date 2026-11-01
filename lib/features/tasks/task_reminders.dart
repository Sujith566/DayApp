import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'tasks_database.dart';
import 'reminder_schedule.dart';

class TaskReminders {
  TaskReminders._();
  static final instance=TaskReminders._();
  final _plugin=FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  Future<void> _queue=Future<void>.value();
  bool _timezoneLoaded=false;
  static const _channel=AndroidNotificationChannel('daynest_tasks_v1','Task reminders',
    description:'Reminders you enable for dated tasks',importance:Importance.high);
  static const _details=NotificationDetails(android:AndroidNotificationDetails(
    'daynest_tasks_v1','Task reminders',channelDescription:'Reminders you enable for dated tasks',
    icon:'ic_task_notification',importance:Importance.high,priority:Priority.high,
    visibility:NotificationVisibility.private));

  Future<void> initialize()async{
    if(!Platform.isAndroid)throw UnsupportedError('Task reminders are configured for Android only.');
    final pending=_initializing;
    if(pending!=null){await pending;return;}
    final future=_init();_initializing=future;
    try{await future;}catch(_){_initializing=null;rethrow;}
  }
  Future<void> _init()async{
    if(!_timezoneLoaded){tzdata.initializeTimeZones();_timezoneLoaded=true;}
    final initialized=await _plugin.initialize(const InitializationSettings(
      android:AndroidInitializationSettings('ic_task_notification')));
    if(initialized!=true)throw StateError('Notification initialization failed');
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()!
      .createNotificationChannel(_channel);
  }
  Future<void> _deviceZone()async{
    await initialize();
    final device=await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(device.identifier));
  }
  Future<bool> requestPermission()async{
    await initialize();
    final android=_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()!;
    final enabled=await android.areNotificationsEnabled();
    if(enabled==true)return true;
    return await android.requestNotificationsPermission()??false;
  }

  Future<String?> validate(DateTime day,int minutes,int lead)async{
    try{
      await _deviceZone();
      final due=tz.TZDateTime(tz.local,day.year,day.month,day.day,minutes~/60,minutes%60);
      if(due.year!=day.year || due.month!=day.month || due.day!=day.day ||
          due.hour!=minutes~/60 || due.minute!=minutes%60){
        return 'That local time does not exist because of a clock change. Choose another time.';
      }
      if(!due.subtract(Duration(minutes:lead)).isAfter(tz.TZDateTime.now(tz.local))){
        return 'Choose a future reminder time, or turn off Remind me.';
      }
      return null;
    }catch(_){return 'Could not prepare reminders. Check notification setup and retry.';}
  }

  // Queue reconciliations and read the latest database inside each run.
  // This prevents an older screen snapshot restoring a cancelled reminder.
  Future<String?> sync(){
    final result=_queue.then((_)=>_syncNow());
    _queue=result.then<void>((_) {},onError:(Object _,StackTrace __){});
    return result;
  }
  Future<String?> _syncNow()async{
    try{
      await _deviceZone();
      final rows=await TasksDatabase.instance.all();
      final now=tz.TZDateTime.now(tz.local);
      final eligible=<(TaskRow,tz.TZDateTime)>[];
      for(final row in rows){
        final fire=reminderTimeForTask(row,tz.local,now:now);
        if(fire!=null)eligible.add((row,fire));
      }
      eligible.sort((a,b)=>a.$2.compareTo(b.$2));
      // Stay below known Android vendor alarm limits. Further tasks remain
      // in the DB and are replenished on launch/resume/refresh.
      final selected=eligible.take(450).toList();
      final wanted=selected.map((r)=>r.$1['id'] as int).toSet();
      final pending=await _plugin.pendingNotificationRequests();
      for(final n in pending){
        if((n.payload??'').startsWith('daynest-task:') && !wanted.contains(n.id))await _plugin.cancel(n.id);
      }
      // Also remove visible alerts for tasks just completed or trashed.
      final allRows=await TasksDatabase.instance.all(trash:true);
      final inactive=[...rows.where((r)=>r['done']==1 || r['reminder_minutes']==null),...allRows];
      for(final r in inactive){await _plugin.cancel(r['id'] as int);}
      final android=_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()!;
      if(await android.areNotificationsEnabled()!=true){
        return eligible.isEmpty?null:'Notifications are off. Enable them in Android Settings, then use Retry reminders.';
      }
      var failed=0;
      for(final item in selected){
        final id=item.$1['id'] as int;
        if(id<1 || id>2147483647){failed++;continue;}
        try{
          await _plugin.zonedSchedule(id,'Task reminder',item.$1['title'] as String,item.$2,_details,
            androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,
            payload:'daynest-task:$id');
        }catch(_){failed++;}
      }
      if(failed>0)return '$failed reminders could not be scheduled. Your tasks are saved. Use Retry reminders.';
      if(eligible.length>450)return 'The next 450 reminders are scheduled. Open Tasks regularly to refresh later ones.';
      return null;
    }catch(_){return 'Tasks are saved, but reminder setup needs a retry. Use Retry reminders from the menu.';}
  }
  Future<String> test()async{
    try{
      if(!await requestPermission())return 'Notifications are off. Enable Daynest notifications in Android Settings.';
      await _plugin.show(0,'Daynest test','Task notifications are enabled.',_details,payload:'daynest-test');
      return 'Test sent. Check the notification shade. Scheduled reminders may arrive late.';
    }catch(_){return 'Could not send the test. Check notification setup and try again.';}
  }
}
