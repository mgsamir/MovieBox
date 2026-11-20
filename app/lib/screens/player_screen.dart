import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PlayerScreen extends StatefulWidget {
 final String? url;
 final String? filePath;
 const PlayerScreen({super.key,this.url,this.filePath}) : assert(url!=null||filePath!=null);
 @override State<PlayerScreen> createState()=>_PlayerScreenState();
}
class _PlayerScreenState extends State<PlayerScreen>{
 late final VideoPlayerController controller;
 String? error;
 @override void initState(){
  super.initState();
  controller=widget.filePath!=null?VideoPlayerController.file(File(widget.filePath!)):VideoPlayerController.networkUrl(Uri.parse(widget.url!));
  controller.initialize().then((_){if(!mounted)return;setState((){});controller.play();}).catchError((Object e){if(mounted)setState(()=>error='This video link could not be played.');});
 }
 @override void dispose(){controller.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(backgroundColor:Colors.black,appBar:AppBar(backgroundColor:Colors.black),body:Center(child:error!=null?Text(error!,style:const TextStyle(color:Colors.white70)):controller.value.isInitialized?AspectRatio(aspectRatio:controller.value.aspectRatio,child:Stack(alignment:Alignment.bottomCenter,children:[VideoPlayer(controller),VideoProgressIndicator(controller,allowScrubbing:true)])):const CircularProgressIndicator()));
}
