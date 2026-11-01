import 'package:flutter/material.dart';
import 'more_store.dart';
import 'more_theme.dart';

class NotesPage extends StatefulWidget{
  const NotesPage({super.key});@override State<NotesPage> createState()=>_NotesPageState();
}
class _NotesPageState extends State<NotesPage>{
  final _store=MoreStore.instance;final _search=TextEditingController();
  List<MoreRow> _notes=[],_folders=[];int _tab=0,_generation=0;int? _folder;
  bool _loading=true,_trash=false,_busy=false;String? _error;
  @override void initState(){super.initState();_search.addListener(_changed);_load();}
  void _changed(){if(mounted)setState((){});}
  @override void dispose(){_search.dispose();super.dispose();}
  Future<void> _load()async{
    if(!mounted)return;final gen=++_generation;setState((){_loading=true;_error=null;});
    try{final rows=await _store.list('notes',trash:_trash);final folders=await _store.folders('notes');
      if(mounted&&gen==_generation)setState((){_notes=rows;_folders=folders;_loading=false;});
    }catch(_){if(mounted&&gen==_generation)setState((){_loading=false;_error='Could not load notes. Please retry.';});}
  }
  Future<void> _run(Future<void> Function() action)async{
    if(_busy)return;setState(()=>_busy=true);
    try{await action();await _load();}catch(_){if(mounted)moreMessage(context,'Could not update notes. Please retry.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _edit([MoreRow? row])async{
    await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>NoteEditor(row:row,folders:_folders,initialFolder:_folder)));
    if(mounted)await _load();
  }
  Future<void> _newFolder()async{
    final name=await moreAskText(context,'New notes folder');if(name!=null&&mounted)await _run(()=>_store.folder('notes',name));
  }
  Future<void> _action(MoreRow row,String action)async{
    if(action=='edit'){await _edit(row);return;}
    if(action=='pin'){await _run(()=>_store.update('notes',row['id'] as int,{'pinned':row['pinned']==1?0:1}));return;}
    if(action=='trash'){
      if(await moreConfirm(context,'Move note to trash?','You can restore it later.')&&mounted)await _run(()=>_store.trash('notes',row['id'] as int,true));
    }else if(action=='restore'){await _run(()=>_store.trash('notes',row['id'] as int,false));}
    else if(action=='delete'&&await moreConfirm(context,'Delete permanently?','This note cannot be recovered.')&&mounted){
      await _run(()async{await _store.remove('notes',row);});
    }
  }
  @override Widget build(BuildContext context)=>MoreSurface(builder:_buildPage);
  Widget _buildPage(BuildContext context){
    final colors=Theme.of(context).colorScheme;
    final query=_search.text.trim().toLowerCase();
    final notes=_notes.where((r)=>(_folder==null||r['folder_id']==_folder)&&(_tab!=1||r['pinned']==1)
      &&'${r['title']} ${r['content']}'.toLowerCase().contains(query)).toList();
    return Scaffold(appBar:AppBar(title:const Text('Notes'),actions:[PopupMenuButton<String>(onSelected:(v){
      if(v=='folder')_newFolder();if(v=='trash'){setState((){_trash=!_trash;_folder=null;_tab=0;});_load();}
    },itemBuilder:(_)=>[const PopupMenuItem(value:'folder',child:Text('New folder')),
      PopupMenuItem(value:'trash',child:Text(_trash?'Back to notes':'Trash'))])]),
      floatingActionButton:_trash?null:FloatingActionButton.extended(onPressed:_busy?null:()=>_edit(),icon:const Icon(Icons.add),label:const Text('New note')),
      body:RefreshIndicator(onRefresh:_load,child:CustomScrollView(physics:const AlwaysScrollableScrollPhysics(),slivers:[
        SliverPadding(padding:const EdgeInsets.symmetric(horizontal:16),sliver:SliverToBoxAdapter(child:Column(
          crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          TextField(controller:_search,decoration:const InputDecoration(hintText:'Search notes…',prefixIcon:Icon(Icons.search))),
          const SizedBox(height:12),Wrap(spacing:8,children:[for(final t in const [(0,'All'),(1,'Pinned'),(2,'Folders')])ChoiceChip(
            selected:_tab==t.$1,label:Text(t.$2),onSelected:(_)=>setState(()=>_tab=t.$1))]),
          if(_trash)const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('Trash · restore or delete permanently')),
          if(_folder!=null)Align(alignment:Alignment.centerLeft,child:InputChip(label:Text(
            _folders.where((f)=>f['id']==_folder).map((f)=>f['name']).firstOrNull as String? ?? 'Folder'),onDeleted:()=>setState(()=>_folder=null))),
          const SizedBox(height:12),
          if(_loading)const Center(child:CircularProgressIndicator())
          else if(_error!=null)Column(children:[Text(_error!),TextButton(onPressed:_load,child:const Text('Retry'))])
          else if(_tab!=2&&notes.isEmpty)const Padding(padding:EdgeInsets.all(32),child:Text('No notes in this view. Capture an idea with New note.',textAlign:TextAlign.center)),
        ]))),
        if(!_loading&&_error==null&&_tab==2)SliverPadding(padding:const EdgeInsets.all(16),sliver:SliverList(delegate:SliverChildBuilderDelegate((context,i){
          final folder=_folders[i];final count=_notes.where((r)=>r['folder_id']==folder['id']).length;
          return Card(child:ListTile(leading:Icon(Icons.folder_outlined,color:colors.primary),title:Text(folder['name'] as String),subtitle:Text('$count notes'),
            onTap:()=>setState((){_folder=folder['id'] as int;_tab=0;}),trailing:IconButton(tooltip:'Delete folder',icon:const Icon(Icons.delete_outline),onPressed:()async{
              if(await moreConfirm(context,'Remove folder?','Notes are kept and moved to All notes.')&&mounted)await _run(()async{
                await _store.deleteFolder(folder['id'] as int);if(_folder==folder['id'])_folder=null;
              });
            })));
        },childCount:_folders.length))),
        if(!_loading&&_error==null&&_tab!=2)SliverPadding(padding:const EdgeInsets.symmetric(horizontal:16),sliver:SliverList(delegate:SliverChildBuilderDelegate((context,i){
          final row=notes[i];return Card(child:InkWell(onTap:_trash?null:()=>_edit(row),child:Padding(padding:const EdgeInsets.fromLTRB(16,6,4,16),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[
              if(row['pinned']==1)Icon(Icons.push_pin,size:15,color:colors.primary),
              Expanded(child:Text(row['title'] as String,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600,fontSize:16))),
              PopupMenuButton<String>(enabled:!_busy,onSelected:(v)=>_action(row,v),itemBuilder:(_)=>_trash?const [
                PopupMenuItem(value:'restore',child:Text('Restore')),PopupMenuItem(value:'delete',child:Text('Delete permanently'))]:[
                  const PopupMenuItem(value:'edit',child:Text('Edit')),PopupMenuItem(value:'pin',child:Text(row['pinned']==1?'Unpin':'Pin')),
                  const PopupMenuItem(value:'trash',child:Text('Move to trash'))])]),
              Text(row['content'] as String,maxLines:4,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:13,height:1.6,color:colors.onSurfaceVariant)),
              const SizedBox(height:10),Text(MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(row['updated_at'] as String).toLocal()),
                style:TextStyle(fontSize:10,color:colors.onSurfaceVariant)),
            ]))));
        },childCount:notes.length))),
        const SliverToBoxAdapter(child:SizedBox(height:100)),
      ])));
  }
}
class NoteEditor extends StatefulWidget{
  final MoreRow? row;final List<MoreRow> folders;final int? initialFolder;
  const NoteEditor({super.key,this.row,required this.folders,this.initialFolder});
  @override State<NoteEditor> createState()=>_NoteEditorState();
}
class _NoteEditorState extends State<NoteEditor>{
  late final _title=TextEditingController(text:widget.row?['title'] as String? ?? '');
  late final _body=TextEditingController(text:widget.row?['content'] as String? ?? '');
  final _form=GlobalKey<FormState>();int? _folder;bool _dirty=false,_busy=false,_leaving=false,_dialog=false;
  @override void initState(){super.initState();_folder=widget.row?['folder_id'] as int? ?? widget.initialFolder;
    for(final c in [_title,_body]){c.addListener((){_dirty=true;});}}
  @override void dispose(){_title.dispose();_body.dispose();super.dispose();}
  void _close(){setState(()=>_leaving=true);WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)Navigator.pop(context);});}
  Future<void> _exit()async{if(_busy||_dialog)return;if(!_dirty){_close();return;}_dialog=true;
    final discard=await moreConfirm(context,'Discard changes?','This note has unsaved changes.');_dialog=false;if(discard&&mounted)_close();}
  Future<void> _save()async{
    if(_busy||!_form.currentState!.validate())return;setState(()=>_busy=true);
    try{await MoreStore.instance.saveNote({'title':_title.text.trim(),'content':_body.text,'folder_id':_folder},id:widget.row?['id'] as int?);if(mounted)_close();}
    catch(_){if(mounted)moreMessage(context,'Could not save. Your writing is still here.');}
    finally{if(mounted&&!_leaving)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>MoreSurface(builder:(context)=>PopScope(canPop:_leaving,
    onPopInvokedWithResult:(didPop,result){if(!didPop)_exit();},child:Scaffold(appBar:AppBar(title:const Text('Your note'),actions:[
      TextButton(onPressed:_busy?null:_save,child:Text(_busy?'Saving…':'Save'))]),body:AbsorbPointer(absorbing:_busy,child:Form(key:_form,
        child:ListView(padding:const EdgeInsets.all(20),children:[
          TextFormField(controller:_title,maxLength:160,style:const TextStyle(fontSize:25,fontWeight:FontWeight.w500),
            decoration:const InputDecoration(hintText:'Untitled note'),validator:(v)=>v==null||v.trim().isEmpty?'Add a title.':null),
          const SizedBox(height:12),DropdownButtonFormField<int>(initialValue:_folder??0,isExpanded:true,
            decoration:const InputDecoration(labelText:'Folder'),items:[const DropdownMenuItem(value:0,child:Text('No folder')),
              for(final f in widget.folders)DropdownMenuItem(value:f['id'] as int,child:Text(f['name'] as String))],
            onChanged:(v){_folder=v==0?null:v;_dirty=true;}),
          const SizedBox(height:20),TextFormField(controller:_body,minLines:15,maxLines:null,textCapitalization:TextCapitalization.sentences,
            decoration:const InputDecoration(hintText:'Capture your thoughts…',border:InputBorder.none,filled:false)),
        ]))))));
}
