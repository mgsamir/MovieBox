import 'dart:io';
import 'package:flutter/material.dart';
import '../services/download_service.dart';
import 'player_screen.dart';

const _bg=Color(0xFF101114),_panel=Color(0xFF1D1F23),_mint=Color(0xFF22D6A0),_muted=Color(0xFF9A9DA5);

class DownloadsScreen extends StatefulWidget {
 const DownloadsScreen({super.key});
 @override State<DownloadsScreen> createState()=>_DownloadsScreenState();
}
class _DownloadsScreenState extends State<DownloadsScreen>{
 final service=DownloadService.instance;
 @override void initState(){super.initState();service.load();}
 @override Widget build(BuildContext context)=>AnimatedBuilder(animation:service,builder:(context,_){
  final tasks=service.tasks;
  return Scaffold(backgroundColor:_bg,appBar:AppBar(backgroundColor:_bg,title:const Text('Downloads'),actions:[IconButton(onPressed:()=>service.load(),icon:const Icon(Icons.refresh))]),
   body:tasks.isEmpty?const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.download_for_offline_outlined,color:_mint,size:54),SizedBox(height:14),Text('No downloads yet',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),SizedBox(height:7),Text('Add a direct video link in My Links and tap Download.',style:TextStyle(color:_muted),textAlign:TextAlign.center)]))
   :ListView.separated(padding:const EdgeInsets.all(16),itemCount:tasks.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(context,index){
    final t=tasks[index];final file=File(t.path);
    return Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:_panel,borderRadius:BorderRadius.circular(15)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Row(children:[const Icon(Icons.movie_outlined,color:_mint),const SizedBox(width:10),Expanded(child:Text(t.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.bold))),PopupMenuButton<String>(onSelected:(v){if(v=='delete')service.delete(t.id);},itemBuilder:(_)=>const [PopupMenuItem(value:'delete',child:Text('Delete download'))])]),
     const SizedBox(height:10),LinearProgressIndicator(value:t.total>0?t.progress:null,color:_mint,backgroundColor:Colors.white12),
     const SizedBox(height:7),Row(children:[Expanded(child:Text(t.isComplete?'Downloaded • Available offline':t.status=='downloading'?'Downloading • ${(t.progress*100).toStringAsFixed(0)}%':t.status=='error'?'Download failed • Tap retry':'Paused • ${(t.progress*100).toStringAsFixed(0)}%',style:const TextStyle(color:_muted,fontSize:12))),if(t.isComplete)IconButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PlayerScreen(filePath:t.path))),icon:const Icon(Icons.play_circle_fill,color:_mint)) else if(t.status=='downloading')IconButton(onPressed:()=>service.pause(t.id),icon:const Icon(Icons.pause_circle_outline,color:_mint)) else IconButton(tooltip:t.status=='error'?'Retry download':'Resume download',onPressed:()=>t.status=='error'?service.retry(t.id):service.resume(t.id),icon:Icon(t.status=='error'?Icons.refresh:Icons.play_circle_outline,color:_mint))]),
    ]));
   }));
 });
}
