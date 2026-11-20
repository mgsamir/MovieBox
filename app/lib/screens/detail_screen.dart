import 'package:flutter/material.dart';
import '../models/content_item.dart';
import 'player_screen.dart';
class DetailScreen extends StatelessWidget {
  final ContentItem item; const DetailScreen({super.key,required this.item});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(item.title)),body:ListView(padding:const EdgeInsets.all(16),children:[
    if(item.posterUrl!=null) Image.network(item.posterUrl!,height:360,fit:BoxFit.contain),
    const SizedBox(height:16),Text(item.title,style:Theme.of(context).textTheme.headlineSmall),
    if(item.synopsis!=null) Text(item.synopsis!),
    if(item.videoUrl!=null) ElevatedButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PlayerScreen(url:item.videoUrl!))),child:const Text('Play authorized video'))
  ]));
}
