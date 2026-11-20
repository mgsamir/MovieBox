import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
class PlayerScreen extends StatefulWidget { final String url; const PlayerScreen({super.key,required this.url}); @override State<PlayerScreen> createState()=>_PlayerScreenState(); }
class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoPlayerController controller;
  @override void initState(){super.initState();controller=VideoPlayerController.networkUrl(Uri.parse(widget.url))..initialize().then((_){if(mounted)setState((){});controller.play();});}
  @override void dispose(){controller.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(),body:Center(child:controller.value.isInitialized?AspectRatio(aspectRatio:controller.value.aspectRatio,child:VideoPlayer(controller)):const CircularProgressIndicator()));
}
