import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;
import '../lib/features/tasks/reminder_schedule.dart';

void main(){
  setUpAll(data.initializeTimeZones);
  Map<String,Object?> task({String date='2026-11-02',int minutes=9*60,int? lead=10,
      int done=0,int deleted=0})=>{'due_date':date,'due_minutes':minutes,
        'reminder_minutes':lead,'done':done,'deleted':deleted};
  test('lead time is subtracted across midnight and month boundaries',(){
    final zone=tz.getLocation('Asia/Kolkata');
    final fire=reminderTimeForTask(task(date:'2026-12-01',minutes:20,lead:60),zone,
      now:tz.TZDateTime(zone,2026,11,30,12));
    expect(fire,tz.TZDateTime(zone,2026,11,30,23,20));
  });
  test('off, completed, deleted, past, and missing time have no alarm',(){
    final zone=tz.getLocation('Asia/Kolkata');final now=tz.TZDateTime(zone,2026,11,2,9);
    for(final row in [task(lead:null),task(done:1),task(deleted:1),task(),
      {...task(),'due_minutes':null}]){
      expect(reminderTimeForTask(row,zone,now:now),isNull);
    }
  });
  test('at task time uses the actual device location offset',(){
    final india=tz.getLocation('Asia/Kolkata');final london=tz.getLocation('Europe/London');
    final a=reminderTimeForTask(task(lead:0),india,now:tz.TZDateTime(india,2026,11,1));
    final b=reminderTimeForTask(task(lead:0),london,now:tz.TZDateTime(london,2026,11,1));
    expect(a!.hour,9);expect(b!.hour,9);
    expect(b.difference(a),const Duration(hours:5,minutes:30));
  });
  test('nonexistent spring-forward time is rejected',(){
    final ny=tz.getLocation('America/New_York');
    expect(reminderTimeForTask(task(date:'2026-03-08',minutes:150,lead:0),ny,
      now:tz.TZDateTime(ny,2026,3,7)),isNull);
  });
}
