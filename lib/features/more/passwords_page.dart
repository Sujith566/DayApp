import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'more_store.dart';
import 'more_theme.dart';
import 'vault_store.dart';
import 'vault_crypto.dart';

class PasswordsPage extends StatefulWidget{
  const PasswordsPage({super.key});@override State<PasswordsPage> createState()=>_PasswordsPageState();
}
class _PasswordsPageState extends State<PasswordsPage> with WidgetsBindingObserver{
  final _vault=VaultStore.instance;final _master=TextEditingController(),_confirm=TextEditingController(),_search=TextEditingController();
  final _title=TextEditingController(),_username=TextEditingController(),_secret=TextEditingController(),_website=TextEditingController(),_note=TextEditingController();
  final _form=GlobalKey<FormState>();List<MoreRow> _entries=[];
  bool _loading=true,_exists=false,_busy=false,_editing=false,_dirty=false,_visible=false,_favourites=false;
  String? _error,_copied;int? _editingId,_reveal;int _epoch=0;Timer? _idle,_clipboardTimer;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_search.addListener(_changed);
    for(final c in [_title,_username,_secret,_website,_note]){c.addListener((){if(_editing)_dirty=true;});}_init();}
  void _changed(){if(mounted)setState((){});}
  Future<void> _init()async{try{final exists=await _vault.exists();if(mounted)setState((){_exists=exists;_loading=false;_error=null;});}
    catch(_){if(mounted)setState((){_loading=false;_error='Could not open the vault. No data has been changed.';});}}
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state!=AppLifecycleState.resumed)_lock();}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);_idle?.cancel();_clipboardTimer?.cancel();_vault.lock();_clearClipboard();
    for(final c in [_master,_confirm,_search,_title,_username,_secret,_website,_note]){c.dispose();}super.dispose();}
  void _touch(){if(!_vault.unlocked)return;_idle?.cancel();_idle=Timer(const Duration(minutes:2),_lock);}
  void _clearEditor(){_editingId=null;_dirty=false;_visible=false;
    for(final c in [_title,_username,_secret,_website,_note]){c.clear();}_dirty=false;}
  void _lock(){
    _epoch++;_vault.lock();_idle?.cancel();_clearClipboard();
    _master.clear();_confirm.clear();_search.clear();_clearEditor();
    if(mounted)setState((){_entries=[];_editing=false;_reveal=null;_busy=false;});
  }
  Future<void> _clearClipboard()async{
    final text=_copied;_copied=null;_clipboardTimer?.cancel();if(text==null)return;
    try{final current=await Clipboard.getData(Clipboard.kTextPlain);if(current?.text==text)await Clipboard.setData(const ClipboardData(text:''));}catch(_){}
  }
  Future<void> _copy(String text)async{
    if(!_vault.unlocked)return;final epoch=_epoch;await Clipboard.setData(ClipboardData(text:text));_copied=text;
    if(epoch!=_epoch||!_vault.unlocked){await _clearClipboard();return;}
    _clipboardTimer?.cancel();_clipboardTimer=Timer(const Duration(seconds:30),_clearClipboard);
    if(mounted)moreMessage(context,'Copied. Daynest will try to clear it after 30 seconds while running.');_touch();
  }
  Future<void> _unlock()async{
    if(_busy)return;
    if(!_exists&&(_master.text.length<12||_master.text!=_confirm.text)){
      moreMessage(context,'Use at least 12 characters and matching confirmation.');return;
    }
    if(_master.text.isEmpty)return;final epoch=_epoch;setState(()=>_busy=true);
    try{await _vault.unlock(_master.text,create:!_exists);final entries=await _vault.entries();
      if(!mounted||epoch!=_epoch)return;_master.clear();_confirm.clear();
      setState((){_exists=true;_entries=entries;_busy=false;_error=null;});_touch();
    }catch(_){if(mounted&&epoch==_epoch){_vault.lock();setState(()=>_busy=false);moreMessage(context,'Could not unlock. Check the master password; a damaged vault also cannot be opened.');await _init();}}
  }
  void _edit([MoreRow? row]){
    _clearEditor();_editingId=row?['id'] as int?;_title.text=row?['title'] as String? ?? '';
    _username.text=row?['username'] as String? ?? '';_secret.text=row?['password'] as String? ?? '';
    _website.text=row?['website'] as String? ?? '';_note.text=row?['note'] as String? ?? '';
    setState((){_editing=true;_dirty=false;_reveal=null;});_touch();
  }
  Future<void> _exitEditor()async{
    if(_busy)return;if(_dirty&&!await moreConfirm(context,'Discard changes?','This password entry has unsaved changes.'))return;
    if(!mounted)return;_clearEditor();setState(()=>_editing=false);
  }
  Future<void> _save()async{
    if(_busy||!_form.currentState!.validate())return;final epoch=_epoch;setState(()=>_busy=true);
    try{final old=_entries.where((r)=>r['id']==_editingId).firstOrNull;
      await _vault.save({'title':_title.text.trim(),'username':_username.text,'password':_secret.text,'website':_website.text.trim(),
        'note':_note.text,'favourite':old?['favourite']??false},id:_editingId);
      final entries=await _vault.entries();if(!mounted||epoch!=_epoch)return;
      _clearEditor();setState((){_editing=false;_entries=entries;_busy=false;});_touch();
    }catch(_){if(mounted&&epoch==_epoch){setState(()=>_busy=false);moreMessage(context,'Could not save. Keep this screen open and retry.');}}
  }
  Future<void> _action(MoreRow row,String action)async{
    if(_busy||!_vault.unlocked)return;if(action=='edit'){_edit(row);return;}
    if(action=='delete'&&!await moreConfirm(context,'Delete password entry?','This encrypted entry will be permanently removed.'))return;
    if(!mounted||!_vault.unlocked)return;final epoch=_epoch;setState(()=>_busy=true);
    try{if(action=='delete'){await _vault.remove(row['id'] as int);}else{
        final data=Map<String,Object?>.from(row)..remove('id');data['favourite']=row['favourite']!=true;await _vault.save(data,id:row['id'] as int);
      }
      final entries=await _vault.entries();if(mounted&&epoch==_epoch)setState((){_entries=entries;_busy=false;_reveal=null;});_touch();
    }catch(_){if(mounted&&epoch==_epoch){setState(()=>_busy=false);moreMessage(context,'Could not update the vault. Please retry.');}}
  }
  @override Widget build(BuildContext context)=>MoreSurface(builder:_buildPage);
  Widget _buildPage(BuildContext context){
    final colors=Theme.of(context).colorScheme;final unlocked=_vault.unlocked;
    final rows=_entries.where((r)=>(!_favourites||r['favourite']==true)&&
      '${r['title']} ${r['username']} ${r['website']}'.toLowerCase().contains(_search.text.toLowerCase().trim())).toList();
    return Listener(onPointerDown:(_)=>_touch(),child:PopScope(canPop:!_editing,
      onPopInvokedWithResult:(didPop,result){if(!didPop)_exitEditor();},child:Scaffold(
      appBar:AppBar(title:Text(_editing?'Password entry':'Passwords'),actions:[
        if(unlocked)IconButton(tooltip:'Lock vault now',onPressed:_lock,icon:const Icon(Icons.lock_outline))]),
      floatingActionButton:unlocked&&!_editing?FloatingActionButton.extended(onPressed:_busy?null:()=>_edit(),
        icon:const Icon(Icons.add),label:const Text('Add password')):null,
      body:AbsorbPointer(absorbing:_busy,child:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Column(mainAxisSize:MainAxisSize.min,
        children:[Padding(padding:const EdgeInsets.all(20),child:Text(_error!)),TextButton(onPressed:_init,child:const Text('Retry'))])):
        !unlocked?ListView(padding:const EdgeInsets.all(24),children:[
          const SizedBox(height:20),Icon(Icons.lock_outline,size:48,color:colors.primary),const SizedBox(height:18),
          Text(_exists?'Your private vault':'Create your private vault',textAlign:TextAlign.center,
            style:const TextStyle(fontSize:24,fontWeight:FontWeight.w500)),const SizedBox(height:12),
          Text(_exists?'Enter your master password to unlock.':'Choose a strong master passphrase. It cannot be recovered if you forget it.',
            textAlign:TextAlign.center,style:TextStyle(height:1.6,color:colors.onSurfaceVariant)),const SizedBox(height:24),
          TextField(controller:_master,obscureText:true,enableSuggestions:false,autocorrect:false,enableIMEPersonalizedLearning:false,
            decoration:const InputDecoration(labelText:'Master password'),onSubmitted:(_){if(_exists)_unlock();}),
          if(!_exists)...[const SizedBox(height:16),TextField(controller:_confirm,obscureText:true,enableSuggestions:false,autocorrect:false,
            enableIMEPersonalizedLearning:false,decoration:const InputDecoration(labelText:'Confirm master password'))],
          const SizedBox(height:20),FilledButton(onPressed:_busy?null:_unlock,child:Text(_busy?'Deriving key…':_exists?'Unlock':'Create vault')),
          const SizedBox(height:18),const Text('AES-256-GCM encryption. Locks when the app loses focus and after 2 minutes without interaction.',
            textAlign:TextAlign.center,style:TextStyle(fontSize:12,height:1.6)),
        ]):_editing?Form(key:_form,child:ListView(padding:const EdgeInsets.all(20),children:[
          TextFormField(controller:_title,maxLength:160,decoration:const InputDecoration(labelText:'Name',hintText:'Google, GitHub, bank login…'),
            validator:(v)=>v==null||v.trim().isEmpty?'Enter a name.':null),const SizedBox(height:12),
          TextFormField(controller:_username,maxLength:300,autocorrect:false,decoration:const InputDecoration(labelText:'Username / email')),
          const SizedBox(height:12),TextFormField(controller:_secret,obscureText:!_visible,maxLength:4096,
            enableSuggestions:false,autocorrect:false,enableIMEPersonalizedLearning:false,
            decoration:InputDecoration(labelText:'Password',suffixIcon:IconButton(tooltip:_visible?'Hide password':'Show password',
              onPressed:()=>setState(()=>_visible=!_visible),icon:Icon(_visible?Icons.visibility_off_outlined:Icons.visibility_outlined))),
            validator:(v)=>v==null||v.isEmpty?'Enter a password.':null),
          Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:_busy?null:(){_secret.text=generateVaultPassword();},
            icon:const Icon(Icons.key),label:const Text('Generate 20-character password'))),
          TextFormField(controller:_website,maxLength:500,decoration:const InputDecoration(labelText:'Website (optional)')),
          const SizedBox(height:12),TextFormField(controller:_note,minLines:2,maxLines:5,maxLength:2000,
            decoration:const InputDecoration(labelText:'Notes (encrypted)')),
          const SizedBox(height:20),FilledButton(onPressed:_busy?null:_save,child:Text(_busy?'Saving…':'Save password')),
          TextButton(onPressed:_busy?null:_exitEditor,child:const Text('Cancel')),
        ])):ListView(padding:const EdgeInsets.fromLTRB(16,0,16,100),children:[
          Card(child:ListTile(leading:Icon(Icons.lock_open_outlined,color:colors.primary),title:const Text('Vault unlocked'),
            subtitle:const Text('Locks automatically after 2 minutes'),trailing:TextButton(onPressed:_lock,child:const Text('Lock')))),
          TextField(controller:_search,decoration:const InputDecoration(hintText:'Search logins…',prefixIcon:Icon(Icons.search))),
          const SizedBox(height:12),Wrap(spacing:8,children:[ChoiceChip(label:const Text('All'),selected:!_favourites,onSelected:(_)=>setState(()=>_favourites=false)),
            ChoiceChip(label:const Text('Favourites'),selected:_favourites,onSelected:(_)=>setState(()=>_favourites=true))]),
          if(_busy)const LinearProgressIndicator(),const SizedBox(height:12),
          if(rows.isEmpty)const Padding(padding:EdgeInsets.all(28),child:Text('No matching logins. Add your first password entry.',textAlign:TextAlign.center)),
          for(final row in rows)Card(child:Padding(padding:const EdgeInsets.fromLTRB(14,8,2,8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[Expanded(child:Text(row['title'] as String,style:const TextStyle(fontWeight:FontWeight.w600))),
              if(row['favourite']==true)Icon(Icons.star,size:17,color:colors.primary),
              PopupMenuButton<String>(enabled:!_busy,onSelected:(v)=>_action(row,v),itemBuilder:(_)=>[
                const PopupMenuItem(value:'edit',child:Text('Edit')),PopupMenuItem(value:'favourite',child:Text(row['favourite']==true?'Unfavourite':'Favourite')),
                const PopupMenuItem(value:'delete',child:Text('Delete'))])]),
            Text(row['username'] as String,style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
            Row(children:[Expanded(child:Text(_reveal==row['id']?row['password'] as String:'••••••••',maxLines:3,overflow:TextOverflow.ellipsis)),
              IconButton(tooltip:'Show / hide password',onPressed:()=>setState(()=>_reveal=_reveal==row['id']?null:row['id'] as int),icon:const Icon(Icons.visibility_outlined,size:19)),
              IconButton(tooltip:'Copy password',onPressed:()=>_copy(row['password'] as String),icon:const Icon(Icons.copy_outlined,size:18))]),
          ]))),
        ])),
    )));
  }
}
