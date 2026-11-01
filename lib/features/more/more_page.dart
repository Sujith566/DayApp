import 'package:flutter/material.dart';
import 'more_theme.dart';
import 'notes_page.dart';
import 'documents_page.dart';
import 'passwords_page.dart';
import 'settings_page.dart';

class DaynestMorePage extends StatelessWidget{
  const DaynestMorePage({super.key});
  @override Widget build(BuildContext context)=>MoreSurface(builder:(context){
    final colors=Theme.of(context).colorScheme;
    final items=<({IconData icon,String title,String description,Widget page})>[
      (icon:Icons.note_alt_outlined,title:'Notes',description:'Ideas, thoughts and things to remember.',page:const NotesPage()),
      (icon:Icons.folder_outlined,title:'Documents',description:'Your important files, organized.',page:const DocumentsPage()),
      (icon:Icons.lock_outline,title:'Passwords',description:'An encrypted vault with a master password.',page:const PasswordsPage()),
      (icon:Icons.settings_outlined,title:'Settings',description:'Appearance, privacy and app information.',page:const SettingsPage()),
    ];
    return Scaffold(appBar:AppBar(automaticallyImplyLeading:false,titleSpacing:20,title:const Text('More',
      style:TextStyle(fontSize:24,fontWeight:FontWeight.w600,letterSpacing:-0.7))),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        Container(padding:const EdgeInsets.all(20),margin:const EdgeInsets.only(bottom:24),
          decoration:BoxDecoration(color:colors.primary.withAlpha(16),borderRadius:BorderRadius.circular(18)),
          child:Row(children:[Icon(Icons.spa_outlined,color:colors.primary,size:30),const SizedBox(width:14),
            const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('A place for the rest of life.',style:TextStyle(fontSize:18,fontWeight:FontWeight.w500)),
              SizedBox(height:6),Text('Keep your everyday essentials close.',style:TextStyle(fontSize:12,height:1.5)),
            ]))])),
        for(final item in items)Card(child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:12),
          leading:CircleAvatar(backgroundColor:colors.primary.withAlpha(16),child:Icon(item.icon,color:colors.primary)),
          title:Text(item.title,style:const TextStyle(fontWeight:FontWeight.w600)),
          subtitle:Padding(padding:const EdgeInsets.only(top:5),child:Text(item.description,style:const TextStyle(fontSize:12,height:1.5))),
          trailing:const Icon(Icons.chevron_right,size:20),onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>item.page)))),
      ]));
  });
}
