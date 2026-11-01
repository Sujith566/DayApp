import 'package:timezone/timezone.dart' as tz;

// Pure scheduling rules: no database writes or Android plugin calls.
tz.TZDateTime? reminderTimeForTask(Map<String,Object?> row,tz.Location zone,
    {required tz.TZDateTime now}){
  if(row['done']==1 || row['deleted']==1)return null;
  final date=row['due_date'];
  final minutes=row['due_minutes'];
  final lead=row['reminder_minutes'];
  if(date is! String || minutes is! int || lead is! int ||
      minutes<0 || minutes>1439 || !(const [0,10,60]).contains(lead))return null;
  final d=DateTime.tryParse(date);
  if(d==null)return null;
  final due=tz.TZDateTime(zone,d.year,d.month,d.day,minutes~/60,minutes%60);
  // Do not silently move a nonexistent daylight-saving clock time.
  if(due.year!=d.year || due.month!=d.month || due.day!=d.day ||
      due.hour!=minutes~/60 || due.minute!=minutes%60)return null;
  final fire=due.subtract(Duration(minutes:lead));
  return fire.isAfter(now)?fire:null;
}
