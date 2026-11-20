import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/content_item.dart';
import '../services/catalog_service.dart';
import 'detail_screen.dart';
import 'personal_links_screen.dart';

const bg = Color(0xFF101114), panel = Color(0xFF1D1F23), muted = Color(0xFF9A9DA5), mint = Color(0xFF22D6A0), blue = Color(0xFF21B7F3);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  CatalogService? service;
  int tab = 0;
  String query = '', type = 'all', watchMode = 'streaming';
  bool loading = true;
  String? error;
  List<ContentItem> catalog = [];
  final Set<String> saved = {};
  final Map<String,double> history = {};

  @override void initState() { super.initState(); restoreLocalData(); load(); }
  Future<void> restoreLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      saved.addAll(prefs.getStringList('moviebox.my_list') ?? const []);
      for (final id in prefs.getStringList('moviebox.watch_history') ?? const []) { history[id] = .01; }
      watchMode = prefs.getString('moviebox.watch_mode') ?? 'streaming';
    });
  }
  Future<void> persistCollections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('moviebox.my_list', saved.toList());
    await prefs.setStringList('moviebox.watch_history', history.keys.toList());
  }
  Future<void> toggleSaved(ContentItem item) async {
    setState(() { if (!saved.add(item.id)) saved.remove(item.id); });
    await persistCollections();
  }
  Future<void> load() async {
    if (!AppConfig.hasSupabaseConfig) { setState(() { loading=false; error='Catalog connection is not configured. Add Supabase build secrets.'; }); return; }
    setState(() { loading=true; error=null; });
    try { final data=await (service ??= CatalogService()).loadAll(limit:150); if (!mounted) return; setState(() { catalog=data; loading=false; }); }
    catch (_) { if (!mounted) return; setState(() { loading=false; error='Could not load catalog. Check your connection and try again.'; }); }
  }
  List<ContentItem> get results => catalog.where((e) => (type=='all' || e.type.toLowerCase()==type) && (query.isEmpty || e.title.toLowerCase().contains(query.toLowerCase()))).toList();
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor:bg,
    body:SafeArea(child:IndexedStack(index:tab,children:[home(),searchPage(),downloads(),me()])),
    bottomNavigationBar:Container(decoration:const BoxDecoration(color:Color(0xFF202126),border:Border(top:BorderSide(color:Colors.white10))),
      child:NavigationBar(height:68,backgroundColor:Colors.transparent,elevation:0,indicatorColor:Colors.transparent,selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),
        labelBehavior:NavigationDestinationLabelBehavior.alwaysShow,destinations:[
          nav(Icons.home_outlined,Icons.home_rounded,'Home'),nav(Icons.search,Icons.search,'Search'),nav(Icons.download_outlined,Icons.download,'Downloads'),nav(Icons.person_outline,Icons.person,'Me')
        ])));
  NavigationDestination nav(IconData a,IconData b,String label)=>NavigationDestination(icon:Icon(a,color:Colors.white70),selectedIcon:Icon(b,color:mint),label:label);

  Widget home()=>RefreshIndicator(onRefresh:load,child:CustomScrollView(slivers:[
    SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(18,12,14,8),child:Row(children:[
      Container(width:38,height:38,decoration:BoxDecoration(borderRadius:BorderRadius.circular(11),gradient:const LinearGradient(colors:[blue,mint])),child:const Icon(Icons.play_arrow,color:Colors.black,size:30)),
      const SizedBox(width:10),const Text('MovieBox',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),const Spacer(),
      IconButton(onPressed:load,icon:const Icon(Icons.refresh,color:Colors.white70)),IconButton(onPressed:()=>setState(()=>tab=3),icon:const Icon(Icons.account_circle_outlined))
    ]))),
    SliverToBoxAdapter(child:searchBar()),
    SliverToBoxAdapter(child:category()),
    SliverToBoxAdapter(child:heroBanner()),
    if(history.isNotEmpty) SliverToBoxAdapter(child:section('Continue Watching',catalog.where((e)=>history.containsKey(e.id)).toList())),
    if(!loading && error==null) ...[
      SliverToBoxAdapter(child:section('Trending Now',results)),
      SliverToBoxAdapter(child:section('Movies',catalog.where((e)=>e.type.toLowerCase()=='movie').toList())),
      SliverToBoxAdapter(child:section('Web Series',catalog.where((e)=>e.type.toLowerCase()=='series').toList())),
      SliverToBoxAdapter(child:section('Anime',catalog.where((e)=>e.type.toLowerCase()=='anime').toList())),
    ],
    if(loading) const SliverToBoxAdapter(child:Padding(padding:EdgeInsets.all(28),child:Center(child:CircularProgressIndicator(color:mint)))),
    if(error!=null) SliverToBoxAdapter(child:message(error!,true)),
    const SliverToBoxAdapter(child:SizedBox(height:24))
  ]));
  Widget searchBar()=>Padding(padding:const EdgeInsets.fromLTRB(18,5,18,13),child:InkWell(onTap:()=>setState(()=>tab=1),borderRadius:BorderRadius.circular(13),
    child:Container(height:52,padding:const EdgeInsets.symmetric(horizontal:15),decoration:BoxDecoration(color:const Color(0xFF343034),borderRadius:BorderRadius.circular(13)),
      child:const Row(children:[Icon(Icons.search,color:Colors.white70,size:25),SizedBox(width:12),Text('Search movies, series, anime...',style:TextStyle(color:Colors.white54)),Spacer(),Text('Search',style:TextStyle(color:mint,fontWeight:FontWeight.bold))]))));
  Widget category()=>SizedBox(height:44,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),children:[chip('For You','all'),chip('Movies','movie'),chip('TV Series','series'),chip('Anime','anime')]));
  Widget chip(String label,String value)=>Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:ChoiceChip(label:Text(label),selected:type==value,onSelected:(_)=>setState(()=>type=value),backgroundColor:panel,selectedColor:mint,side:BorderSide.none,labelStyle:TextStyle(color:type==value?Colors.black:Colors.white70,fontWeight:FontWeight.w600)));
  Widget heroBanner(){
    final item=results.isNotEmpty?results.first:(catalog.isNotEmpty?catalog.first:null);
    return Padding(padding:const EdgeInsets.fromLTRB(16,12,16,12),child:ClipRRect(borderRadius:BorderRadius.circular(18),child:SizedBox(height:220,child:Stack(fit:StackFit.expand,children:[
      if(item?.posterUrl!=null) Image.network(item!.posterUrl!,fit:BoxFit.cover,errorBuilder:(_,__,___)=>bannerBg()) else bannerBg(),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.centerRight,end:Alignment.centerLeft,colors:[Colors.transparent,Color(0xE6000000)]))),
      Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('MOVIEBOX ORIGINAL',style:TextStyle(color:mint,letterSpacing:2,fontWeight:FontWeight.bold,fontSize:10)),const Spacer(),
        Text(item?.title??'Discover something great',maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:25,fontWeight:FontWeight.w900)),
        const SizedBox(height:7),Text(item==null?'Movies • Series • Anime':[item.type,if(item.year!=null)item.year.toString(),if(item.language!=null)item.language!].join('  •  '),style:const TextStyle(color:Colors.white70,fontSize:12)),
        const SizedBox(height:13),if(item!=null) FilledButton.icon(onPressed:()=>open(item),style:FilledButton.styleFrom(backgroundColor:mint,foregroundColor:Colors.black),icon:const Icon(Icons.play_arrow),label:const Text('Watch now'))
      ]))
    ]))));
  }
  Widget bannerBg()=>const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF254D53),Color(0xFF34233D),Color(0xFF17191D)])));
  Widget section(String title,List<ContentItem> items){
    if(items.isEmpty)return const SizedBox.shrink();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Padding(padding:const EdgeInsets.fromLTRB(18,12,16,10),child:Row(children:[Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),const Spacer(),const Icon(Icons.chevron_right,color:Colors.white54)])),
      SizedBox(height:205,child:ListView.separated(padding:const EdgeInsets.symmetric(horizontal:16),scrollDirection:Axis.horizontal,itemCount:items.length>12?12:items.length,separatorBuilder:(_,__)=>const SizedBox(width:11),itemBuilder:(_,i)=>poster(items[i])))
    ]);
  }
  Widget poster(ContentItem item)=>InkWell(onTap:()=>open(item),borderRadius:BorderRadius.circular(12),child:SizedBox(width:124,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(12),child:SizedBox(width:124,child:item.posterUrl==null?posterFallback():Image.network(item.posterUrl!,fit:BoxFit.cover,errorBuilder:(_,__,___)=>posterFallback())))),
    const SizedBox(height:7),Text(item.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:12)),
    Text([if(item.year!=null)item.year.toString(),item.type].join(' • '),maxLines:1,style:const TextStyle(color:muted,fontSize:10))
  ])));
  Widget posterFallback()=>Container(color:const Color(0xFF27292E),child:const Center(child:Icon(Icons.movie_outlined,size:34,color:Colors.white38)));

  Widget searchPage()=>Column(children:[
    const Padding(padding:EdgeInsets.fromLTRB(18,18,18,12),child:Align(alignment:Alignment.centerLeft,child:Text('Search',style:TextStyle(fontSize:25,fontWeight:FontWeight.w900)))),
    Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:TextField(onChanged:(v)=>setState(()=>query=v),decoration:InputDecoration(hintText:'What do you want to watch?',prefixIcon:const Icon(Icons.search),filled:true,fillColor:panel,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none)))),
    const SizedBox(height:10),SizedBox(height:44,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),children:[chip('All','all'),chip('Movies','movie'),chip('Series','series'),chip('Anime','anime')])),
    Expanded(child:loading?const Center(child:CircularProgressIndicator(color:mint)):error!=null?message(error!,true):GridView.builder(padding:const EdgeInsets.all(16),itemCount:results.length,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,childAspectRatio:.57,crossAxisSpacing:10,mainAxisSpacing:14),itemBuilder:(_,i)=>poster(results[i])))
  ]);
  Widget downloads()=>empty(Icons.download_for_offline_outlined,'Downloads','Your offline videos will appear here once downloaded.');
  Widget me()=>ListView(padding:const EdgeInsets.fromLTRB(18,18,18,28),children:[
    const Text('Me',style:TextStyle(fontSize:26,fontWeight:FontWeight.w900)),const SizedBox(height:18),
    Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(18)),child:const Row(children:[
      CircleAvatar(radius:27,backgroundColor:mint,child:Icon(Icons.person,color:Colors.black,size:30)),SizedBox(width:14),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('MovieBox User',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),SizedBox(height:4),Text('Your personal entertainment space',style:TextStyle(color:muted,fontSize:12))])),Icon(Icons.chevron_right,color:Colors.white54)
    ])),
    const SizedBox(height:18),
    menu(Icons.history,'Watch History','${history.length} titles',()=>collection('Watch History',history.keys.toSet())),
    menu(Icons.bookmark_border,'My List','${saved.length}',()=>collection('My List',saved)),
    menu(Icons.link,'My Links','Add and manage your own video links',()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const PersonalLinksScreen()))),
    const SizedBox(height:14),menu(Icons.settings_outlined,'Settings','App preferences and playback options',settings),
    menu(Icons.info_outline,'About MovieBox','Version 0.1.0',()=>info('About MovieBox','MovieBox for Android — movies, series and anime.'))
  ]);
  Widget menu(IconData icon,String title,String sub,VoidCallback tap)=>Container(margin:const EdgeInsets.only(bottom:9),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(15)),child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:5),leading:Icon(icon,color:Colors.white70,size:25),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(sub,style:const TextStyle(color:muted,fontSize:11)),trailing:const Icon(Icons.chevron_right,color:Colors.white60),onTap:tap));
  void settings()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SettingsPage(mode:watchMode,onMode:(v) async {setState(()=>watchMode=v);final p=await SharedPreferences.getInstance();await p.setString('moviebox.watch_mode',v);})));
  void collection(String title,Set<String> ids){final list=catalog.where((e)=>ids.contains(e.id)).toList();Navigator.push(context,MaterialPageRoute(builder:(_)=>CollectionPage(title:title,items:list,onOpen:open)));}
  void open(ContentItem item){setState(()=>history[item.id]=history[item.id]??.01);persistCollections();Navigator.push(context,MaterialPageRoute(builder:(_)=>DetailScreen(item:item,isSaved:saved.contains(item.id),onToggleSaved:()=>toggleSaved(item))));}
  Widget empty(IconData icon,String title,String text)=>Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(icon,color:mint,size:54),const SizedBox(height:14),Text(title,style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const SizedBox(height:7),Text(text,style:const TextStyle(color:muted))]));
  Widget message(String text,bool retry)=>Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off_outlined,size:42,color:muted),const SizedBox(height:12),Text(text,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white70)),if(retry)TextButton.icon(onPressed:load,icon:const Icon(Icons.refresh),label:const Text('Try again'))])));
  void info(String title,String text)=>showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:panel,title:Text(title),content:Text(text),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('OK'))]));
}

class CollectionPage extends StatelessWidget {
  final String title;final List<ContentItem> items;final ValueChanged<ContentItem> onOpen;
  const CollectionPage({super.key,required this.title,required this.items,required this.onOpen});
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:bg,appBar:AppBar(backgroundColor:bg,title:Text(title)),body:items.isEmpty?const Center(child:Text('Nothing here yet',style:TextStyle(color:muted))):ListView.builder(itemCount:items.length,itemBuilder:(_,i)=>ListTile(onTap:()=>onOpen(items[i]),leading:SizedBox(width:48,child:items[i].posterUrl==null?const Icon(Icons.movie):Image.network(items[i].posterUrl!,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.movie))),title:Text(items[i].title),subtitle:Text(items[i].type,style:const TextStyle(color:muted)),trailing:const Icon(Icons.play_circle_outline))));
}

class SettingsPage extends StatefulWidget {
  final String mode;final ValueChanged<String> onMode;
  const SettingsPage({super.key,required this.mode,required this.onMode});
  @override State<SettingsPage> createState()=>_SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage>{
  late String mode;bool notifications=true,background=true,mini=true;
  @override void initState(){super.initState();mode=widget.mode;}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:bg,appBar:AppBar(backgroundColor:bg,title:const Text('Settings')),body:ListView(padding:const EdgeInsets.all(16),children:[
    const Padding(padding:EdgeInsets.fromLTRB(4,8,4,12),child:Text('Your app and preferences',style:TextStyle(color:muted))),
    tile(Icons.notifications_none,'Notifications',trailing:Switch(value:notifications,activeColor:mint,onChanged:(v)=>setState(()=>notifications=v))),
    tile(Icons.language,'Language',trailing:const Text('Device default',style:TextStyle(color:muted)),tap:languageOptions),
    tile(Icons.play_circle_outline,'Watch Options',trailing:Text(mode=='streaming'?'Streaming':'Download',style:const TextStyle(color:muted)),tap:watchOptions),
    const SizedBox(height:18),
    SwitchListTile(contentPadding:const EdgeInsets.symmetric(horizontal:12),tileColor:panel,activeColor:mint,value:background,onChanged:(v)=>setState(()=>background=v),title:const Text('Download in background')),
    const SizedBox(height:8),
    SwitchListTile(contentPadding:const EdgeInsets.symmetric(horizontal:12),tileColor:panel,activeColor:mint,value:mini,onChanged:(v)=>setState(()=>mini=v),title:const Text('Auto activate Miniplayer'),subtitle:const Text('Keep the miniplayer active when switching pages.',style:TextStyle(color:muted))),
    const SizedBox(height:24),const Padding(padding:EdgeInsets.fromLTRB(4,8,4,12),child:Text('More info and support',style:TextStyle(color:muted))),
    tile(Icons.privacy_tip_outlined,'Privacy'),tile(Icons.help_outline,'Help & Support'),tile(Icons.info_outline,'About MovieBox',trailing:const Text('0.1.0',style:TextStyle(color:muted))),
    const SizedBox(height:22),Container(height:52,decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),gradient:const LinearGradient(colors:[blue,mint])),child:const Center(child:Text('MovieBox',style:TextStyle(color:Colors.black,fontWeight:FontWeight.w900,fontSize:17))))
  ]));
  Widget tile(IconData icon,String title,{Widget? trailing,VoidCallback? tap})=>Container(margin:const EdgeInsets.only(bottom:2),decoration:const BoxDecoration(color:panel),child:ListTile(leading:Icon(icon,color:Colors.white70),title:Text(title),trailing:trailing??const Icon(Icons.chevron_right,color:Colors.white54),onTap:tap));
  void languageOptions()=>showModalBottomSheet(context:context,backgroundColor:panel,builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[for(final lang in ['Device default','English','Hindi','Tamil','Telugu','Malayalam','Kannada','Bengali']) ListTile(title:Text(lang),onTap:()=>Navigator.pop(ctx))])));
  void watchOptions()=>showModalBottomSheet(context:context,backgroundColor:panel,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>Padding(padding:const EdgeInsets.fromLTRB(20,20,20,30),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('Watch Options',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('Choose how videos should open by default.',style:TextStyle(color:muted)),const SizedBox(height:16),
    RadioListTile<String>(value:'streaming',groupValue:mode,activeColor:mint,title:const Text('Streaming'),subtitle:const Text('Play videos online instantly'),onChanged:(v)=>update(()=>mode=v!)),
    RadioListTile<String>(value:'download',groupValue:mode,activeColor:mint,title:const Text('Download'),subtitle:const Text('Download first, then watch offline'),onChanged:(v)=>update(()=>mode=v!)),
    const SizedBox(height:10),SizedBox(width:double.infinity,child:FilledButton(onPressed:(){widget.onMode(mode);Navigator.pop(ctx);},child:const Text('Save')))
  ]))));
}
