import 'dart:convert';
import 'package:flutter/material.dart';
import 'tasks_database.dart';
import 'task_reminders.dart';

ThemeData tasksTheme(BuildContext context) {
  final base=Theme.of(context);
  final dark=base.brightness==Brightness.dark;
  final colors=ColorScheme.fromSeed(seedColor:const Color(0xFF174F43),brightness:base.brightness).copyWith(
    primary:dark?const Color(0xFF9ED7C0):const Color(0xFF174F43),
    onPrimary:dark?const Color(0xFF103D31):Colors.white,
    surface:dark?const Color(0xFF17211E):const Color(0xFFFCFAF5),
    surfaceContainerHighest:dark?const Color(0xFF26332E):const Color(0xFFEEEDE7),
    outlineVariant:dark?const Color(0xFF35443D):const Color(0xFFE8E6DE));
  return base.copyWith(colorScheme:colors,scaffoldBackgroundColor:colors.surface,
    appBarTheme:AppBarTheme(backgroundColor:colors.surface,foregroundColor:colors.onSurface,
      centerTitle:false,elevation:0,scrolledUnderElevation:0),
    cardTheme:CardThemeData(color:colors.surface,elevation:0,margin:const EdgeInsets.only(bottom:10),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14),side:BorderSide(color:colors.outlineVariant))),
    floatingActionButtonTheme:FloatingActionButtonThemeData(backgroundColor:colors.primary,
      foregroundColor:colors.onPrimary,shape:const StadiumBorder(),elevation:3),
    inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:colors.surfaceContainerHighest,
      border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none),
      enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none),
      focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide(color:colors.primary))));
}

String taskTime(BuildContext context,int minutes)=>MaterialLocalizations.of(context)
  .formatTimeOfDay(TimeOfDay(hour:minutes~/60,minute:minutes%60),
    alwaysUse24HourFormat:MediaQuery.alwaysUse24HourFormatOf(context));

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});
  @override
  State<TasksPage> createState()=>_TasksPageState();
}

class _TasksPageState extends State<TasksPage> with WidgetsBindingObserver {
  final _db=TasksDatabase.instance;
  final _search=TextEditingController();
  List<TaskRow> _tasks=[];
  int _tab=0,_generation=0;
  bool _loading=true,_busy=false,_showSearch=false,_showCompleted=true,_trash=false;
  String? _error,_reminderWarning;
  String _priority='',_category='';
  DateTime _selected=DateUtils.dateOnly(DateTime.now());
  late DateTime _month=DateTime(_selected.year,_selected.month);
  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_search.addListener(_changed);_load();}
  void _changed(){if(mounted)setState((){});}
  @override
  void dispose(){WidgetsBinding.instance.removeObserver(this);_search.dispose();super.dispose();}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed)_load();}
  Future<void> _load()async{
    if(!mounted)return;
    final generation=++_generation;
    final trash=_trash;
    setState((){_loading=true;_error=null;});
    try{
      final rows=await _db.all(trash:trash);
      final warning=await TaskReminders.instance.sync();
      if(!mounted || generation!=_generation)return;
      setState((){_tasks=rows;_loading=false;_reminderWarning=warning;});
    }catch(_){if(mounted && generation==_generation)setState((){_loading=false;_error='Could not load your tasks. Please retry.';});}
  }
  void _message(String text){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
  Future<void> _mutate(Future<void> Function() action)async{
    if(_busy)return;
    setState(()=>_busy=true);
    try{await action();await _load();}catch(_){_message('Could not update this task. Please retry.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<bool> _confirm(String title,String message)async=>await showDialog<bool>(context:context,
    builder:(context)=>AlertDialog(title:Text(title),content:Text(message),actions:[
      TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Confirm'))]))??false;

  Future<void> _edit({TaskRow? row})async{
    if(_busy)return;
    if(row!=null){
      try{row=await _db.get(row['id'] as int);}
      catch(_){_message('Could not open this task.');return;}
      if(row==null){_message('This task is no longer available.');return;}
    }
    if(!mounted)return;
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>TaskEditor(row:row,
      initialDate:_tab==1?DateUtils.dateOnly(DateTime.now().add(const Duration(days:1))):_selected)));
    if(mounted)await _load();
  }
  Future<void> _open(TaskRow row)async{
    if(_trash || _busy)return;
    final result=await Navigator.of(context).push<String>(MaterialPageRoute(builder:(_)=>TaskDetail(id:row['id'] as int)));
    if(!mounted)return;
    if(result=='edit')await _edit(row:row);else await _load();
  }
  Future<void> _action(TaskRow row,String action)async{
    if(_busy)return;
    final id=row['id'] as int;
    if(action=='edit'){await _edit(row:row);return;}
    if(action=='trash'){
      if(await _confirm('Move task to trash?','You can restore it later.') && mounted)await _mutate(()=>_db.trash(id));
    }else if(action=='restore'){await _mutate(()=>_db.restore(id));}
    else if(action=='delete'){
      if(await _confirm('Delete permanently?','This cannot be undone.') && mounted)await _mutate(()=>_db.remove(id));
    }
  }
  List<TaskRow> get _filtered{
    final today=taskDay(DateTime.now());
    final selected=taskDay(_selected);
    final query=_search.text.trim().toLowerCase();
    final rows=_tasks.where((r){
      final due=r['due_date'] as String?;
      final dateMatch=_trash || (_tab==1?due!=null && due.compareTo(today)>0
        : _tab==2?due==selected
        : due==selected || due==null || (r['done']==0 && due.compareTo(selected)<0));
      final text=[r['title'],r['note'],r['category'],...taskChecklist(r).map((c)=>c['text'])].join(' ').toLowerCase();
      return dateMatch && (_priority.isEmpty || r['priority']==_priority)
        && (_category.isEmpty || r['category']==_category) && (query.isEmpty || text.contains(query));
    }).toList();
    const order={'High':0,'Normal':1,'Low':2};
    rows.sort((a,b){
      var n=(a['done'] as int).compareTo(b['done'] as int);if(n!=0)return n;
      n=(a['due_date'] as String? ?? '9999').compareTo(b['due_date'] as String? ?? '9999');if(n!=0)return n;
      n=(order[a['priority']]??1).compareTo(order[b['priority']]??1);if(n!=0)return n;
      n=(a['due_minutes'] as int? ?? 1440).compareTo(b['due_minutes'] as int? ?? 1440);
      return n!=0?n:(b['id'] as int).compareTo(a['id'] as int);
    });
    return rows;
  }
  void _day(int offset){
    final d=DateTime(_selected.year,_selected.month,_selected.day+offset);
    if(d.year<1900 || d.year>2100)return;
    setState((){_selected=d;_month=DateTime(d.year,d.month);});
  }
  void _monthStep(int offset){
    final m=DateTime(_month.year,_month.month+offset);
    if(m.year<1900 || m.year>2100)return;
    setState((){_month=m;_selected=m;});
  }
  void _reset(){_search.clear();setState((){_priority='';_category='';});}
  void _menu(String v){
    if(v=='completed'){setState(()=>_showCompleted=!_showCompleted);}
    if(v=='trash'){setState(()=>_trash=!_trash);_load();}
    if(v=='reset')_reset();
    if(v=='today')setState((){_tab=0;_selected=DateUtils.dateOnly(DateTime.now());_month=DateTime(_selected.year,_selected.month);});
    if(v=='refresh' || v=='reminders')_load();
    if(v=='test')TaskReminders.instance.test().then(_message);
  }

  Widget _tabs(BuildContext context){
    final colors=Theme.of(context).colorScheme;
    return Container(padding:const EdgeInsets.all(4),
      decoration:BoxDecoration(color:colors.surfaceContainerHighest,borderRadius:BorderRadius.circular(26)),
      child:Row(children:[for(final item in const [(0,'Today'),(1,'Upcoming'),(2,'Calendar')])
        Expanded(child:Semantics(selected:_tab==item.$1,button:true,
          child:Material(color:_tab==item.$1?colors.primary:Colors.transparent,borderRadius:BorderRadius.circular(24),
            child:InkWell(borderRadius:BorderRadius.circular(24),onTap:()=>setState(()=>_tab=item.$1),
              child:Padding(padding:const EdgeInsets.symmetric(vertical:13,horizontal:3),child:Text(item.$2,
                textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:_tab==item.$1?colors.onPrimary:colors.onSurfaceVariant)))))))]));
  }

  Widget _calendar(BuildContext context){
    final first=DateTime(_month.year,_month.month);
    final offset=first.weekday-1;
    final days=DateTime(_month.year,_month.month+1,0).day;
    final cells=((offset+days+6)~/7)*7;
    final colors=Theme.of(context).colorScheme;
    final marked=_tasks.where((r)=>r['done']==0).map((r)=>r['due_date']).toSet();
    return Column(children:[
      Row(children:[IconButton(tooltip:'Previous month',onPressed:_month.year==1900&&_month.month==1?null:()=>_monthStep(-1),icon:const Icon(Icons.chevron_left)),
        Expanded(child:Text(MaterialLocalizations.of(context).formatMonthYear(_month),textAlign:TextAlign.center,
          style:const TextStyle(fontSize:14,fontWeight:FontWeight.w600))),
        IconButton(tooltip:'Next month',onPressed:_month.year==2100&&_month.month==12?null:()=>_monthStep(1),icon:const Icon(Icons.chevron_right))]),
      Row(children:[for(final name in const ['M','T','W','T','F','S','S'])
        Expanded(child:Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(name,textAlign:TextAlign.center,
          style:TextStyle(fontSize:11,color:colors.onSurfaceVariant))))]),
      for(var week=0;week<cells~/7;week++)Row(children:[for(var col=0;col<7;col++)Expanded(child:Builder(builder:(context){
        final day=week*7+col-offset+1;
        if(day<1 || day>days)return const SizedBox(height:50);
        final date=DateTime(_month.year,_month.month,day);
        final active=DateUtils.isSameDay(date,_selected);
        final hasTasks=marked.contains(taskDay(date));
        return Semantics(selected:active,label:'${MaterialLocalizations.of(context).formatFullDate(date)}${hasTasks?', has pending tasks':''}',
          child:InkWell(borderRadius:BorderRadius.circular(10),onTap:()=>setState(()=>_selected=date),
            child:Container(constraints:const BoxConstraints(minHeight:50),margin:const EdgeInsets.all(2),
              padding:const EdgeInsets.symmetric(vertical:8),decoration:BoxDecoration(
                color:active?colors.primary:Colors.transparent,borderRadius:BorderRadius.circular(10)),
              child:Column(children:[Text('$day',style:TextStyle(color:active?colors.onPrimary:colors.onSurface)),
                const SizedBox(height:4),Container(width:4,height:4,decoration:BoxDecoration(shape:BoxShape.circle,
                  color:hasTasks?(active?colors.onPrimary:colors.primary):Colors.transparent))]))));
      }))]),
    ]);
  }

  Widget _taskCard(BuildContext context,TaskRow row){
    final colors=Theme.of(context).colorScheme;
    final done=row['done']==1;
    final due=row['due_date'] as String?;
    final overdue=!done && due!=null && due.compareTo(taskDay(DateTime.now()))<0;
    final checks=taskChecklist(row);
    final time=row['due_minutes'] as int?;
    final subtitle=<String>[
      if(due==null)'No date' else if(overdue)'Overdue · ${MaterialLocalizations.of(context).formatShortDate(DateTime.parse(due))}'
        else MaterialLocalizations.of(context).formatShortDate(DateTime.parse(due)),
      if(time!=null)taskTime(context,time),
      if(checks.isNotEmpty)'${checks.where((c)=>c['done']==true).length}/${checks.length} steps',
      if(row['reminder_minutes']!=null && !done)
        due!=null && time!=null && DateTime.parse(due).add(Duration(minutes:time-(row['reminder_minutes'] as int))).isAfter(DateTime.now())
          ? 'Reminder on' : 'Reminder time passed',
    ].join(' · ');
    final priority=row['priority'] as String;
    return Card(key:ValueKey(row['id']),child:Padding(padding:const EdgeInsets.fromLTRB(0,8,2,8),
      child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Checkbox(value:done,onChanged:_trash||_busy?null:(value)=>_mutate(()=>_db.toggle(row['id'] as int,value??false))),
        Expanded(child:InkWell(onTap:_trash?null:()=>_open(row),borderRadius:BorderRadius.circular(10),
          child:Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(row['title'] as String,style:TextStyle(fontSize:14,fontWeight:FontWeight.w600,
              decoration:done?TextDecoration.lineThrough:null,color:done?colors.onSurfaceVariant:colors.onSurface)),
            if((row['note'] as String).isNotEmpty)Padding(padding:const EdgeInsets.only(top:4),
              child:Text(row['note'] as String,maxLines:2,overflow:TextOverflow.ellipsis,
                style:TextStyle(fontSize:12,height:1.45,color:colors.onSurfaceVariant))),
            const SizedBox(height:5),Text(subtitle,style:TextStyle(fontSize:11,height:1.4,color:overdue?colors.error:colors.onSurfaceVariant)),
            const SizedBox(height:7),Wrap(spacing:6,runSpacing:4,children:[
              if(priority!='Normal')_badge(context,priority,priority=='High'?colors.error:colors.onSurfaceVariant),
              if((row['category'] as String).isNotEmpty)_badge(context,row['category'] as String,colors.primary),
              if(done)_badge(context,'Done',colors.primary),
            ]),
          ])))),
        PopupMenuButton<String>(enabled:!_busy,tooltip:'Task actions',onSelected:(a)=>_action(row,a),
          itemBuilder:(_)=>_trash?const [PopupMenuItem(value:'restore',child:Text('Restore')),
            PopupMenuItem(value:'delete',child:Text('Delete permanently'))]:const [
              PopupMenuItem(value:'edit',child:Text('Edit')),PopupMenuItem(value:'trash',child:Text('Move to trash'))]),
      ])));
  }
  Widget _badge(BuildContext context,String label,Color color)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(
      color:color.withAlpha(20),borderRadius:BorderRadius.circular(6)),
    child:Text(label,style:TextStyle(fontSize:10,color:color)));

  @override
  Widget build(BuildContext context)=>Theme(data:tasksTheme(context),child:Builder(builder:_buildPage));
  Widget _buildPage(BuildContext context){
    final colors=Theme.of(context).colorScheme;
    final filtered=_filtered;
    final rows=filtered.where((r)=>_trash || _showCompleted || r['done']==0).toList();
    final completed=filtered.where((r)=>r['done']==1).length;
    final categories=_tasks.map((r)=>r['category'] as String).where((c)=>c.isNotEmpty).toSet().toList()..sort();
    return Scaffold(
      appBar:AppBar(automaticallyImplyLeading:false,titleSpacing:20,
        title:Text(_trash?'Task trash':'Tasks',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w600,letterSpacing:-0.7)),
        actions:[IconButton(tooltip:'Search tasks',icon:Icon(_showSearch?Icons.close:Icons.search),onPressed:()=>setState((){
          _showSearch=!_showSearch;if(!_showSearch)_search.clear();})),
          PopupMenuButton<String>(onSelected:_menu,itemBuilder:(_)=>[
            const PopupMenuItem(value:'today',child:Text('Go to today')),
            PopupMenuItem(value:'completed',child:Text(_showCompleted?'Hide completed':'Show completed')),
            PopupMenuItem(value:'trash',child:Text(_trash?'Back to tasks':'Trash')),
            const PopupMenuItem(value:'reset',child:Text('Reset filters')),
            const PopupMenuItem(value:'refresh',child:Text('Refresh')),
            const PopupMenuItem(value:'reminders',child:Text('Retry reminders')),
            const PopupMenuItem(value:'test',child:Text('Test notification'))])]),
      floatingActionButton:_trash?null:FloatingActionButton.extended(onPressed:_busy?null:()=>_edit(),
        icon:const Icon(Icons.add),label:const Text('Add task')),
      body:SafeArea(top:false,child:RefreshIndicator(onRefresh:_load,child:CustomScrollView(
        physics:const AlwaysScrollableScrollPhysics(),slivers:[
          SliverPadding(padding:const EdgeInsets.symmetric(horizontal:16),sliver:SliverToBoxAdapter(
            child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              if(!_trash)_tabs(context),
              if(_showSearch)...[
                const SizedBox(height:12),TextField(controller:_search,decoration:const InputDecoration(
                  hintText:'Search tasks and checklists…',prefixIcon:Icon(Icons.search))),
                const SizedBox(height:8),Wrap(spacing:8,children:[
                  PopupMenuButton<String>(onSelected:(v)=>setState(()=>_priority=v),itemBuilder:(_)=>[
                    const PopupMenuItem(value:'',child:Text('Any priority')),
                    for(final p in const ['High','Normal','Low'])PopupMenuItem(value:p,child:Text(p))],
                    child:Chip(label:Text(_priority.isEmpty?'Priority ▾':'$_priority ▾'))),
                  PopupMenuButton<String>(onSelected:(v)=>setState(()=>_category=v),itemBuilder:(_)=>[
                    const PopupMenuItem(value:'',child:Text('Any category')),
                    for(final c in categories)PopupMenuItem(value:c,child:Text(c))],
                    child:Chip(label:Text(_category.isEmpty?'Category ▾':'$_category ▾'))),
                ]),
              ],
              if(!_trash && _tab==2)_calendar(context)
              else if(!_trash && _tab==0)Row(children:[
                IconButton(tooltip:'Previous day',onPressed:()=>_day(-1),icon:const Icon(Icons.chevron_left,size:20)),
                Expanded(child:TextButton(onPressed:()async{
                  final d=await showDatePicker(context:context,initialDate:_selected,firstDate:DateTime(1900),lastDate:DateTime(2100,12,31));
                  if(d!=null && mounted)setState((){_selected=d;_month=DateTime(d.year,d.month);});
                },child:Text(MaterialLocalizations.of(context).formatMediumDate(_selected),
                  style:TextStyle(fontSize:13,color:colors.onSurface,fontWeight:FontWeight.w600)))),
                IconButton(tooltip:'Next day',onPressed:()=>_day(1),icon:const Icon(Icons.chevron_right,size:20))])
              else if(!_trash)const Padding(padding:EdgeInsets.symmetric(vertical:18),
                child:Text('Scheduled after today',style:TextStyle(fontSize:13,fontWeight:FontWeight.w500))),
              if(_priority.isNotEmpty || _category.isNotEmpty)Wrap(spacing:8,children:[
                if(_priority.isNotEmpty)InputChip(label:Text(_priority),onDeleted:()=>setState(()=>_priority='')),
                if(_category.isNotEmpty)InputChip(label:Text(_category),onDeleted:()=>setState(()=>_category='')),
              ]),
              if(!_loading && _error==null && !_trash && filtered.isNotEmpty)...[
                Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Row(children:[
                  Expanded(child:Text('$completed of ${filtered.length} completed',style:TextStyle(fontSize:11,color:colors.onSurfaceVariant))),
                  if(!_showCompleted)const Text('Completed hidden',style:TextStyle(fontSize:10))])),
                ClipRRect(borderRadius:BorderRadius.circular(5),child:LinearProgressIndicator(
                  value:completed/filtered.length,minHeight:4,backgroundColor:colors.surfaceContainerHighest)),
                const SizedBox(height:16),
              ],
              if(!_trash && _tab==0)Padding(padding:const EdgeInsets.only(bottom:12),
                child:Text('Includes unfinished earlier tasks and tasks without a date.',
                  style:TextStyle(fontSize:10,height:1.5,color:colors.onSurfaceVariant))),
              if(_trash)const Padding(padding:EdgeInsets.symmetric(vertical:16),child:Text('Restore tasks or delete them permanently.',style:TextStyle(fontSize:12))),
              if(_reminderWarning!=null)Card(child:Padding(padding:const EdgeInsets.all(14),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(_reminderWarning!,style:const TextStyle(fontSize:12,height:1.5)),
                  TextButton(onPressed:_load,child:const Text('Retry reminders'))]))),
              if(_busy)const LinearProgressIndicator(),
              if(_loading)const Padding(padding:EdgeInsets.all(36),child:Center(child:CircularProgressIndicator()))
              else if(_error!=null)Column(children:[Text(_error!),TextButton(onPressed:_load,child:const Text('Retry'))])
              else if(rows.isEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:42,horizontal:18),child:Column(children:[
                Icon(_trash?Icons.delete_outline:Icons.check_circle_outline,size:38,color:colors.primary),
                const SizedBox(height:16),Text(_trash?'Your trash is empty':filtered.isNotEmpty?'All visible tasks are complete':'A little room to focus',
                  textAlign:TextAlign.center,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w500)),
                const SizedBox(height:8),Text(_trash?'Removed tasks will appear here.':filtered.isNotEmpty?'Show completed tasks from the menu.'
                  :'Add a task or try another date or filter.',textAlign:TextAlign.center,
                  style:TextStyle(fontSize:12,height:1.6,color:colors.onSurfaceVariant)),
                if(_priority.isNotEmpty || _category.isNotEmpty || _search.text.isNotEmpty)
                  TextButton(onPressed:_reset,child:const Text('Reset filters')),
              ])),
            ]))),
          if(!_loading && _error==null)SliverPadding(padding:const EdgeInsets.symmetric(horizontal:16),
            sliver:SliverList(delegate:SliverChildBuilderDelegate((context,i)=>_taskCard(context,rows[i]),childCount:rows.length))),
          const SliverToBoxAdapter(child:SizedBox(height:100)),
        ]))),
    );
  }
}

class TaskEditor extends StatefulWidget {
  final TaskRow? row;
  final DateTime initialDate;
  const TaskEditor({super.key,this.row,required this.initialDate});
  @override
  State<TaskEditor> createState()=>_TaskEditorState();
}
class _TaskEditorState extends State<TaskEditor>{
  final _form=GlobalKey<FormState>();
  late final TextEditingController _title,_note,_category,_checklist;
  DateTime? _date;
  TimeOfDay? _time;
  String _priority='Normal';
  int? _reminder;
  bool _busy=false,_dirty=false,_leaving=false,_exitDialog=false;
  @override
  void initState(){
    super.initState();final row=widget.row;
    _title=TextEditingController(text:row?['title'] as String? ?? '');
    _note=TextEditingController(text:row?['note'] as String? ?? '');
    _category=TextEditingController(text:row?['category'] as String? ?? '');
    _checklist=TextEditingController(text:row==null?'':taskChecklist(row).map((c)=>c['text']).join('\n'));
    _priority=row?['priority'] as String? ?? 'Normal';
    _reminder=row?['reminder_minutes'] as int?;
    final date=row?['due_date'] as String?;
    _date=row==null?widget.initialDate:date==null?null:DateTime.parse(date);
    final minutes=row?['due_minutes'] as int?;
    _time=minutes==null?null:TimeOfDay(hour:minutes~/60,minute:minutes%60);
    for(final c in [_title,_note,_category,_checklist]){c.addListener(_changed);}
  }
  void _changed(){if(mounted && !_dirty)setState(()=>_dirty=true);}
  @override
  void dispose(){_title.dispose();_note.dispose();_category.dispose();_checklist.dispose();super.dispose();}
  void _close(bool saved){setState(()=>_leaving=true);WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)Navigator.pop(context,saved);});}
  Future<void> _exit()async{
    if(_busy || _leaving || _exitDialog)return;
    if(!_dirty){_close(false);return;}
    _exitDialog=true;
    final discard=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:const Text('Discard unsaved changes?'),content:const Text('This task has not been saved yet.'),actions:[
        TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Keep editing')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Discard'))]));
    _exitDialog=false;if(discard==true && mounted)_close(false);
  }
  List<String> get _lines=>_checklist.text.split('\n').map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
  Future<void> _save()async{
    if(_busy || !_form.currentState!.validate())return;
    setState(()=>_busy=true);
    try{
      if(_reminder!=null){
        if(_date==null || _time==null){
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Choose a date and time for the reminder.')));
          return;
        }
        final problem=await TaskReminders.instance.validate(_date!,_time!.hour*60+_time!.minute,_reminder!);
        if(!mounted)return;
        if(problem!=null){
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(problem)));
          return;
        }
      }
      // Match old checklist items by text and consume matches so duplicates
      // retain their own state when the list is edited or reordered.
      final old=widget.row==null?<Map<String,Object?>>[]:taskChecklist(widget.row!);
      final originalChecks=jsonEncode(old);
      final checks=<Map<String,Object?>>[];
      for(final line in _lines){
        final index=old.indexWhere((c)=>c['text']==line);
        final done=index>=0?old.removeAt(index)['done']==true:false;
        checks.add({'text':line,'done':done});
      }
      await TasksDatabase.instance.save({
        'title':_title.text.trim(),'note':_note.text.trim(),'category':_category.text.trim(),
        'reminder_minutes':_reminder,
        'priority':_priority,'due_date':_date==null?null:taskDay(_date!),
        'due_minutes':_date==null || _time==null?null:_time!.hour*60+_time!.minute,
        'checklist':jsonEncode(checks),
        'done':checks.isNotEmpty && jsonEncode(checks)!=originalChecks
          ? (checks.every((c)=>c['done']==true)?1:0)
          : (widget.row?['done'] as int? ?? 0),
      },id:widget.row?['id'] as int?);
      final warning=await TaskReminders.instance.sync();
      if(mounted){
        if(warning!=null)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(warning)));
        _close(true);
      }
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:Text('Could not save this task. Your text is still here. Please retry.')));}
    finally{if(mounted && !_leaving)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Theme(data:tasksTheme(context),child:Builder(builder:_buildEditor));
  Widget _buildEditor(BuildContext context)=>PopScope(canPop:_leaving,
    onPopInvokedWithResult:(didPop,result){if(!didPop)_exit();},child:Scaffold(
      appBar:AppBar(title:Text(widget.row==null?'New task':'Edit task'),actions:[
        Padding(padding:const EdgeInsets.only(right:12),child:FilledButton(onPressed:_busy?null:_save,
          child:Text(_busy?'Saving…':'Save')))]),
      body:SafeArea(top:false,child:AbsorbPointer(absorbing:_busy,child:Form(key:_form,
        child:ListView(padding:const EdgeInsets.all(20),children:[
          TextFormField(controller:_title,autofocus:widget.row==null,maxLength:160,
            textCapitalization:TextCapitalization.sentences,
            style:const TextStyle(fontSize:22,fontWeight:FontWeight.w500),
            decoration:const InputDecoration(labelText:'Task',hintText:'What do you want to get done?'),
            validator:(v)=>v==null || v.trim().isEmpty?'Enter a task title.':null),
          const SizedBox(height:12),
          TextFormField(controller:_note,minLines:2,maxLines:5,maxLength:2000,
            textCapitalization:TextCapitalization.sentences,
            decoration:const InputDecoration(labelText:'Notes (optional)',alignLabelWithHint:true)),
          const SizedBox(height:12),
          DropdownButtonFormField<String>(value:_priority,decoration:const InputDecoration(labelText:'Priority'),
            items:const [DropdownMenuItem(value:'High',child:Text('High')),
              DropdownMenuItem(value:'Normal',child:Text('Normal')),DropdownMenuItem(value:'Low',child:Text('Low'))],
            onChanged:(v){if(v!=null)setState((){_priority=v;_dirty=true;});}),
          const SizedBox(height:18),
          TextFormField(controller:_category,maxLength:40,textCapitalization:TextCapitalization.words,
            decoration:const InputDecoration(labelText:'Category (optional)',hintText:'Work, Personal, Learning…')),
          const SizedBox(height:8),
          Wrap(spacing:6,children:[for(final c in const ['Work','Personal','Learning'])ActionChip(
            label:Text(c),onPressed:(){_category.text=c;_changed();})]),
          const SizedBox(height:12),
          Row(children:[Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.calendar_today_outlined,size:18),
            label:Text(_date==null?'No date':MaterialLocalizations.of(context).formatMediumDate(_date!)),
            onPressed:()async{
              final d=await showDatePicker(context:context,initialDate:_date??DateTime.now(),
                firstDate:DateTime(1900),lastDate:DateTime(2100,12,31));
              if(d!=null && mounted)setState((){_date=d;_dirty=true;});
            })),if(_date!=null)IconButton(tooltip:'Remove date and time',icon:const Icon(Icons.close),
              onPressed:()=>setState((){_date=null;_time=null;_reminder=null;_dirty=true;}))]),
          const SizedBox(height:8),
          Row(children:[Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.schedule,size:18),
            label:Text(_time==null?'Add time (optional)':taskTime(context,_time!.hour*60+_time!.minute)),
            onPressed:_date==null?null:()async{
              final t=await showTimePicker(context:context,initialTime:_time??TimeOfDay.now());
              if(t!=null && mounted)setState((){_time=t;_dirty=true;});
            })),if(_time!=null)IconButton(tooltip:'Remove time',icon:const Icon(Icons.close),
              onPressed:()=>setState((){_time=null;_reminder=null;_dirty=true;}))]),
          const SizedBox(height:8),
          SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,
            title:const Text('Remind me'),
            subtitle:Text(_date==null || _time==null?'Add a date and time first.':'Offline notification · Android may deliver it late.'),
            value:_reminder!=null,
            onChanged:_date==null || _time==null || _busy?null:(enabled)async{
              if(!enabled){setState((){_reminder=null;_dirty=true;});return;}
              setState(()=>_busy=true);
              try{
                final allowed=await TaskReminders.instance.requestPermission();
                if(!mounted)return;
                if(allowed){setState((){_reminder=0;_dirty=true;});}
                else{ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text(
                  'Notifications are off. Enable Daynest notifications in Android Settings to use reminders.')));}
              }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not enable reminders. Check setup and retry.')));}
              finally{if(mounted)setState(()=>_busy=false);}
            }),
          if(_reminder!=null)...[
            DropdownButtonFormField<int>(value:_reminder,
              decoration:const InputDecoration(labelText:'Notify me'),
              items:const [DropdownMenuItem(value:0,child:Text('At task time')),
                DropdownMenuItem(value:10,child:Text('10 minutes before')),
                DropdownMenuItem(value:60,child:Text('1 hour before'))],
              onChanged:(v){if(v!=null)setState((){_reminder=v;_dirty=true;});}),
            const Padding(padding:EdgeInsets.symmetric(vertical:10),child:Text(
              'Android battery settings can delay reminders. Do not rely on them for critical alarms.',
              style:TextStyle(fontSize:11,height:1.5))),
          ],
          const SizedBox(height:8),
          TextFormField(controller:_checklist,minLines:4,maxLines:12,
            textCapitalization:TextCapitalization.sentences,
            decoration:const InputDecoration(labelText:'Checklist (optional)',hintText:'One step per line',
              helperText:'Up to 50 steps. Tap a saved task to check them off.',alignLabelWithHint:true),
            validator:(_)=>_lines.length>50?'Use up to 50 checklist steps.':
              _lines.any((line)=>line.length>200)?'Keep each step under 200 characters.':null),
          const SizedBox(height:24),
          FilledButton.icon(onPressed:_busy?null:_save,icon:const Icon(Icons.check),label:Text(_busy?'Saving…':'Save task')),
        ]))))));
}

class TaskDetail extends StatefulWidget {
  final int id;
  const TaskDetail({super.key,required this.id});
  @override
  State<TaskDetail> createState()=>_TaskDetailState();
}
class _TaskDetailState extends State<TaskDetail>{
  TaskRow? _task;
  bool _loading=true,_busy=false;
  String? _error;
  @override
  void initState(){super.initState();_load();}
  Future<void> _load()async{
    try{
      final row=await TasksDatabase.instance.get(widget.id);
      if(mounted)setState((){_task=row;_loading=false;_error=null;});
    }catch(_){if(mounted)setState((){_loading=false;_error='Could not load this task.';});}
  }
  Future<void> _update(Future<void> Function() action)async{
    if(_busy)return;setState(()=>_busy=true);
    try{
      await action();
      final warning=await TaskReminders.instance.sync();
      if(warning!=null && mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(warning)));
      await _load();
    }
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not update. Please retry.')));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Theme(data:tasksTheme(context),child:Builder(builder:_buildDetail));
  Widget _buildDetail(BuildContext context){
    final row=_task;
    return Scaffold(appBar:AppBar(title:const Text('Task'),actions:[
      IconButton(tooltip:'Edit task',onPressed:row==null||_busy?null:()=>Navigator.pop(context,'edit'),icon:const Icon(Icons.edit_outlined))]),
      body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Column(mainAxisSize:MainAxisSize.min,
        children:[Text(_error!),TextButton(onPressed:_load,child:const Text('Retry'))])):row==null?const Center(child:Text('This task is no longer available.')):
        ListView(padding:const EdgeInsets.all(20),children:[
          if(_busy)const LinearProgressIndicator(),
          Text(row['title'] as String,style:Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height:12),
          Wrap(spacing:8,runSpacing:4,children:[Chip(label:Text(row['priority'] as String)),
            if((row['category'] as String).isNotEmpty)Chip(label:Text(row['category'] as String))]),
          const SizedBox(height:10),
          Text(row['due_date']==null?'No date':MaterialLocalizations.of(context).formatFullDate(DateTime.parse(row['due_date'] as String))),
          if(row['due_minutes']!=null)Text(taskTime(context,row['due_minutes'] as int)),
          if(row['reminder_minutes']!=null)Padding(padding:const EdgeInsets.only(top:8),
            child:Text(row['done']==1?'Reminder inactive · task completed':
              'Reminder: ${row['reminder_minutes']==0?'at task time':'${row['reminder_minutes']} minutes before'} · approximate Android delivery',
              style:const TextStyle(fontSize:12,height:1.5))),
          const SizedBox(height:18),
          if((row['note'] as String).isNotEmpty)SelectableText(row['note'] as String),
          const SizedBox(height:16),
          for(final indexed in taskChecklist(row).asMap().entries)CheckboxListTile(
            contentPadding:EdgeInsets.zero,controlAffinity:ListTileControlAffinity.leading,
            title:Text(indexed.value['text'] as String),value:indexed.value['done']==true,
            onChanged:_busy?null:(v)=>_update(()=>TasksDatabase.instance.toggleCheck(widget.id,indexed.key,v??false))),
          const SizedBox(height:20),
          FilledButton.icon(onPressed:_busy?null:()=>_update(()=>TasksDatabase.instance.toggle(widget.id,row['done']!=1)),
            icon:Icon(row['done']==1?Icons.undo:Icons.check),label:Text(row['done']==1?'Mark unfinished':'Complete task')),
        ]));
  }
}
