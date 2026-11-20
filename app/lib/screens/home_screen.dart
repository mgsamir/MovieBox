import 'package:flutter/material.dart';
import '../models/content_item.dart';
import '../services/catalog_service.dart';
import 'detail_screen.dart';
class HomeScreen extends StatefulWidget { const HomeScreen({super.key}); @override State<HomeScreen> createState()=>_HomeScreenState(); }
class _HomeScreenState extends State<HomeScreen> {
  final service=CatalogService(); int tab=0; String search='';
  final types=['movie','series','anime']; final labels=['Movies','Series','Anime'];
  @override Widget build(BuildContext context)=>Scaffold(
    appBar: AppBar(title: const Text('CineBox')),
    body: Column(children:[
      Padding(padding: const EdgeInsets.all(12),child: TextField(decoration: const InputDecoration(hintText:'Search titles',prefixIcon:Icon(Icons.search)),onChanged:(v)=>setState(()=>search=v))),
      NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [NavigationDestination(icon:Icon(Icons.movie),label:'Movies'),NavigationDestination(icon:Icon(Icons.tv),label:'Series'),NavigationDestination(icon:Icon(Icons.animation),label:'Anime')]),
      Expanded(child:FutureBuilder<List<ContentItem>>(future:service.load(types[tab],query:search),builder:(c,s){
        if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return Center(child:Text('Error: ${s.error}'));
        final items=s.data??[];
        if(items.isEmpty)return const Center(child:Text('No titles yet. Run catalog sync.'));
        return GridView.builder(padding:const EdgeInsets.all(12),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,childAspectRatio:.66,crossAxisSpacing:12,mainAxisSpacing:12),itemCount:items.length,itemBuilder:(c,i){
          final x=items[i]; return InkWell(onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DetailScreen(item:x))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Expanded(child: x.posterUrl==null?const ColoredBox(color:Colors.black26,child:Center(child:Icon(Icons.movie))):Image.network(x.posterUrl!,fit:BoxFit.cover,width:double.infinity,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image))),
            Text(x.title,maxLines:2,overflow:TextOverflow.ellipsis),Text(x.year?.toString()??labels[tab],style:Theme.of(context).textTheme.bodySmall)
          ]));
        });
      }))
    ]));
}
