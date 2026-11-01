import 'package:flutter/material.dart';
ThemeData moreTheme(BuildContext context){
  final base=Theme.of(context);final dark=base.brightness==Brightness.dark;
  final c=ColorScheme.fromSeed(seedColor:const Color(0xFF174F43),brightness:base.brightness).copyWith(
    primary:dark?const Color(0xFF9ED7C0):const Color(0xFF174F43),onPrimary:dark?const Color(0xFF103D31):Colors.white,
    surface:dark?const Color(0xFF17211E):const Color(0xFFFCFAF5),
    surfaceContainerHighest:dark?const Color(0xFF26332E):const Color(0xFFEEEDE7),
    outlineVariant:dark?const Color(0xFF35443D):const Color(0xFFE8E6DE));
  return base.copyWith(colorScheme:c,scaffoldBackgroundColor:c.surface,
    appBarTheme:AppBarTheme(backgroundColor:c.surface,foregroundColor:c.onSurface,centerTitle:false,elevation:0,scrolledUnderElevation:0),
    cardTheme:CardThemeData(color:c.surface,elevation:0,margin:const EdgeInsets.only(bottom:12),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14),side:BorderSide(color:c.outlineVariant))),
    floatingActionButtonTheme:FloatingActionButtonThemeData(backgroundColor:c.primary,foregroundColor:c.onPrimary,shape:const StadiumBorder()),
    inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:c.surfaceContainerHighest,
      border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none)));
}
Future<bool> moreConfirm(BuildContext context,String title,String message)async=>await showDialog<bool>(context:context,
  builder:(context)=>AlertDialog(title:Text(title),content:Text(message),actions:[
    TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
    FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Confirm'))]))??false;
void moreMessage(BuildContext context,String message)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
class MoreSurface extends StatelessWidget{
  final WidgetBuilder builder;const MoreSurface({super.key,required this.builder});
  @override
  Widget build(BuildContext context)=>Theme(data:moreTheme(context),child:Builder(builder:builder));
}
Future<String?> moreAskText(BuildContext context,String title,{String initial=''})=>showDialog<String>(
  context:context,builder:(_)=>_TextPrompt(title:title,initial:initial));
class _TextPrompt extends StatefulWidget{
  final String title,initial;const _TextPrompt({required this.title,required this.initial});
  @override State<_TextPrompt> createState()=>_TextPromptState();
}
class _TextPromptState extends State<_TextPrompt>{
  late final _text=TextEditingController(text:widget.initial);
  @override void dispose(){_text.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:Text(widget.title),content:TextField(controller:_text,autofocus:true,maxLength:50),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:(){if(_text.text.trim().isNotEmpty)Navigator.pop(context,_text.text.trim());},child:const Text('Save'))]);
}
