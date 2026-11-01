import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'more_store.dart';
import 'more_theme.dart';

class DocumentsPage extends StatefulWidget{
  const DocumentsPage({super.key});@override State<DocumentsPage> createState()=>_DocumentsPageState();
}
class _DocumentsPageState extends State<DocumentsPage>{
  final _store=MoreStore.instance;final _search=TextEditingController();
  List<MoreRow> _documents=[],_folders=[];bool _loading=true,_busy=false,_trash=false;
  int _tab=0,_generation=0;int? _folder;String? _error;
  @override void initState(){super.initState();_search.addListener(_changed);_load();}
  void _changed(){if(mounted)setState((){});}
  @override void dispose(){_search.dispose();super.dispose();}
  Future<void> _load()async{if(!mounted)return;final gen=++_generation;setState((){_loading=true;_error=null;});
    try{final rows=await _store.list('documents',trash:_trash);final folders=await _store.folders('documents');
      if(mounted&&gen==_generation)setState((){_documents=rows;_folders=folders;_loading=false;});
    }catch(_){if(mounted&&gen==_generation)setState((){_loading=false;_error='Could not load documents.';});}}
  Future<void> _run(Future<void> Function() action)async{
    if(_busy)return;setState(()=>_busy=true);try{await action();await _load();}
    catch(_){if(mounted)moreMessage(context,'Could not finish. Your existing documents are kept.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _import()async=>_run(()async{
    final file=await FilePicker.pickFile(dialogTitle:'Import a document');if(file==null)return;
    final length=await file.length();if(length!=null&&length>25*1024*1024){if(mounted)moreMessage(context,'Use a file under 25 MB.');return;}
    await _store.importDocument(name:file.name,stream:file.readAsByteStream(),folderId:_folder);
  });
  Future<void> _open(MoreRow row)async{
    if(_busy)return;
    if(!await moreConfirm(context,'Open in a viewer app?','The selected viewer will receive access to this document. Continue?')||!mounted)return;
    await _run(()async{
      final file=await _store.documentFile(row['file_name'] as String);
      if(!await file.exists()){if(mounted)moreMessage(context,'The document copy is unavailable.');return;}
      final result=await OpenFilex.open(file.path);
      if(result.type!=ResultType.done&&mounted)moreMessage(context,'No viewer opened this file. Install a compatible PDF/image/document viewer.');
    });
  }
  Future<void> _action(MoreRow row,String action)async{
    if(action=='star'){await _run(()=>_store.update('documents',row['id'] as int,{'starred':row['starred']==1?0:1}));}
    if(action=='edit'){
      final data=await showDialog<MoreRow>(context:context,builder:(_)=>_DocumentEditor(row:row,folders:_folders));
      if(data!=null&&mounted)await _run(()=>_store.update('documents',row['id'] as int,data));
    }
    if(action=='trash'&&await moreConfirm(context,'Move document to trash?','The imported file stays available for restoration.')&&mounted){
      await _run(()=>_store.trash('documents',row['id'] as int,true));
    }
    if(action=='restore')await _run(()=>_store.trash('documents',row['id'] as int,false));
    if(action=='delete'&&await moreConfirm(context,'Delete permanently?','The imported copy will be deleted. The original file outside Daynest is kept.')&&mounted){
      await _run(()async{final cleaned=await _store.remove('documents',row);if(!cleaned&&mounted)moreMessage(context,'Record deleted; the unused file needs later cleanup.');});
    }
  }
  Future<void> _newFolder()async{final name=await moreAskText(context,'New document folder');if(name!=null&&mounted)await _run(()=>_store.folder('documents',name));}
  @override Widget build(BuildContext context)=>MoreSurface(builder:_buildPage);
  Widget _buildPage(BuildContext context){
    final colors=Theme.of(context).colorScheme;final query=_search.text.toLowerCase().trim();
    final rows=_documents.where((r)=>(_folder==null||r['folder_id']==_folder)&&(_tab!=1||r['starred']==1)
      &&'${r['title']} ${r['original_name']} ${r['note']}'.toLowerCase().contains(query)).toList();
    final today=DateUtils.dateOnly(DateTime.now());
    final expiring=_documents.where((r)=>r['expires']!=null&&DateTime.parse(r['expires'] as String).difference(today).inDays<=90).length;
    return Scaffold(appBar:AppBar(title:const Text('Documents'),actions:[PopupMenuButton<String>(onSelected:(v){
      if(v=='folder')_newFolder();if(v=='trash'){setState((){_trash=!_trash;_tab=0;_folder=null;});_load();}
    },itemBuilder:(_)=>[const PopupMenuItem(value:'folder',child:Text('New folder')),
      PopupMenuItem(value:'trash',child:Text(_trash?'Back to documents':'Trash'))])]),
      floatingActionButton:_trash?null:FloatingActionButton.extended(onPressed:_busy?null:_import,icon:const Icon(Icons.file_upload_outlined),label:const Text('Import')),
      body:RefreshIndicator(onRefresh:_load,child:CustomScrollView(physics:const AlwaysScrollableScrollPhysics(),slivers:[
        SliverPadding(padding:const EdgeInsets.symmetric(horizontal:16),sliver:SliverToBoxAdapter(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          TextField(controller:_search,decoration:const InputDecoration(hintText:'Search documents…',prefixIcon:Icon(Icons.search))),
          const SizedBox(height:12),Wrap(spacing:8,children:[for(final t in const [(0,'All'),(1,'Starred'),(2,'Folders')])ChoiceChip(
            label:Text(t.$2),selected:_tab==t.$1,onSelected:(_)=>setState(()=>_tab=t.$1))]),
          if(_folder!=null)Align(alignment:Alignment.centerLeft,child:InputChip(label:const Text('Folder selected'),onDeleted:()=>setState(()=>_folder=null))),
          if(_trash)const Padding(padding:EdgeInsets.all(12),child:Text('Trash · restore or delete permanently')),
          if(!_trash&&expiring>0)Card(color:colors.errorContainer,child:Padding(padding:const EdgeInsets.all(14),
            child:Text('$expiring documents are expired or expire within 90 days.',style:TextStyle(color:colors.onErrorContainer)))),
          const SizedBox(height:12),if(_busy)const LinearProgressIndicator(),
          if(_loading)const Padding(padding:EdgeInsets.all(28),child:Center(child:CircularProgressIndicator()))
          else if(_error!=null)Column(children:[Text(_error!),TextButton(onPressed:_load,child:const Text('Retry'))])
          else if(_tab!=2&&rows.isEmpty)const Padding(padding:EdgeInsets.all(32),child:Text('No documents in this view. Import a file to keep a private copy.',textAlign:TextAlign.center)),
        ]))),
        if(!_loading&&_error==null&&_tab==2)SliverPadding(padding:const EdgeInsets.all(16),sliver:SliverList(delegate:SliverChildBuilderDelegate((context,i){
          final f=_folders[i];return Card(child:ListTile(leading:Icon(Icons.folder_outlined,color:colors.primary),title:Text(f['name'] as String),
            subtitle:Text('${_documents.where((r)=>r['folder_id']==f['id']).length} files'),onTap:()=>setState((){_folder=f['id'] as int;_tab=0;}),
            trailing:IconButton(tooltip:'Remove folder',icon:const Icon(Icons.delete_outline),onPressed:()async{
              if(await moreConfirm(context,'Remove folder?','Documents are kept in All documents.')&&mounted)await _run(()async{
                await _store.deleteFolder(f['id'] as int);if(_folder==f['id'])_folder=null;
              });
            })));
        },childCount:_folders.length))),
        if(!_loading&&_error==null&&_tab!=2)SliverPadding(padding:const EdgeInsets.symmetric(horizontal:16),sliver:SliverList(delegate:SliverChildBuilderDelegate((context,i){
          final r=rows[i];final expiry=r['expires'] as String?;
          return Card(child:ListTile(contentPadding:const EdgeInsets.fromLTRB(14,8,2,8),
            leading:Icon(Icons.description_outlined,color:colors.primary),title:Text(r['title'] as String,maxLines:2,overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontSize:14,fontWeight:FontWeight.w600)),
            subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('${((r['size'] as int)/1024).toStringAsFixed(0)} KB · ${r['original_name']}',maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11)),
              if(expiry!=null)Text('Expires ${MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(expiry))}',style:TextStyle(fontSize:11,
                color:DateTime.parse(expiry).isBefore(today)?colors.error:colors.onSurfaceVariant)),
              if(r['starred']==1)Icon(Icons.star,size:15,color:colors.primary),
            ]),onTap:_trash?null:()=>_open(r),
            trailing:PopupMenuButton<String>(enabled:!_busy,onSelected:(v)=>_action(r,v),itemBuilder:(_)=>_trash?const[
              PopupMenuItem(value:'restore',child:Text('Restore')),PopupMenuItem(value:'delete',child:Text('Delete permanently'))]:[
                const PopupMenuItem(value:'edit',child:Text('Details / expiry')),PopupMenuItem(value:'star',child:Text(r['starred']==1?'Unstar':'Star')),
                const PopupMenuItem(value:'trash',child:Text('Move to trash'))])));
        },childCount:rows.length))),
        const SliverToBoxAdapter(child:SizedBox(height:100)),
      ])));
  }
}
class _DocumentEditor extends StatefulWidget{
  final MoreRow row;final List<MoreRow> folders;const _DocumentEditor({required this.row,required this.folders});
  @override State<_DocumentEditor> createState()=>_DocumentEditorState();
}
class _DocumentEditorState extends State<_DocumentEditor>{
  final _form=GlobalKey<FormState>();late final _title=TextEditingController(text:widget.row['title'] as String);
  late final _note=TextEditingController(text:widget.row['note'] as String);int? _folder;DateTime? _expiry;
  @override void initState(){super.initState();_folder=widget.row['folder_id'] as int?;
    _expiry=widget.row['expires']==null?null:DateTime.parse(widget.row['expires'] as String);}
  @override void dispose(){_title.dispose();_note.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Document details'),content:SingleChildScrollView(child:Form(key:_form,
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextFormField(controller:_title,maxLength:160,decoration:const InputDecoration(labelText:'Title'),validator:(v)=>v==null||v.trim().isEmpty?'Add a title.':null),
      DropdownButtonFormField<int>(initialValue:_folder??0,isExpanded:true,decoration:const InputDecoration(labelText:'Folder'),items:[
        const DropdownMenuItem(value:0,child:Text('No folder')),for(final f in widget.folders)DropdownMenuItem(value:f['id'] as int,child:Text(f['name'] as String))],
        onChanged:(v)=>_folder=v==0?null:v),
      const SizedBox(height:12),TextField(controller:_note,minLines:2,maxLines:4,maxLength:1000,decoration:const InputDecoration(labelText:'Note')),
      TextButton.icon(icon:const Icon(Icons.event_outlined),label:Text(_expiry==null?'Add expiry date':MaterialLocalizations.of(context).formatMediumDate(_expiry!)),onPressed:()async{
        final d=await showDatePicker(context:context,initialDate:_expiry??DateTime.now(),firstDate:DateTime(1900),lastDate:DateTime(2100,12,31));
        if(d!=null&&mounted)setState(()=>_expiry=d);
      }),if(_expiry!=null)TextButton(onPressed:()=>setState(()=>_expiry=null),child:const Text('Remove expiry')),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:(){if(_form.currentState!.validate())Navigator.pop(context,{'title':_title.text.trim(),'note':_note.text.trim(),
        'folder_id':_folder,'expires':_expiry?.toIso8601String().substring(0,10)});},child:const Text('Save'))]);
}
