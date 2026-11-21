import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/content_item.dart';
import '../services/catalog_service.dart';
import 'detail_screen.dart';
import 'personal_links_screen.dart';
import 'downloads_screen.dart';

const bg = Color(0xFF101114), panel = Color(0xFF1D1F23), muted = Color(0xFF9A9DA5), mint = Color(0xFF22D6A0), blue = Color(0xFF21B7F3);

const _searchHint = 'Search movies, series, anime...';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CatalogService? service;
  int tab = 0;
  String watchMode = 'streaming';
  bool loading = true;
  String? error;
  List<ContentItem> catalog = [];
  final catalogNotifier = ValueNotifier<List<ContentItem>>([]);
  final Set<String> saved = {};
  final Map<String, double> history = {};

  @override void initState() { super.initState(); restoreLocalData(); load(); }
  @override void dispose() { catalogNotifier.dispose(); super.dispose(); }

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
    setState(() { loading = true; error = null; });
    try {
      final data = await (service ??= CatalogService()).loadAll(limit: 150);
      if (!mounted) return;
      catalogNotifier.value = data;
      setState(() {
        catalog = data;
        loading = false;
        error = data.isEmpty
            ? 'Catalog is empty or unavailable. Pull down to retry when internet is connected.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Could not load catalogue. Check internet and pull down to retry.';
      });
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    body: SafeArea(child: IndexedStack(index: tab, children: [home(), const DownloadsScreen(), me()])),
    bottomNavigationBar: Container(
      decoration: const BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: NavigationBar(
        height: 68,
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          nav(Icons.home_outlined, Icons.home_rounded, 'Home'),
          nav(Icons.download_outlined, Icons.download, 'Downloads'),
          nav(Icons.person_outline, Icons.person, 'Me'),
        ],
      ),
    ),
  );
  NavigationDestination nav(IconData a, IconData b, String label) => NavigationDestination(
    icon: Icon(a, color: Colors.white70), selectedIcon: Icon(b, color: mint), label: label);

  // ---------------- Home ----------------
  Widget home() => RefreshIndicator(onRefresh: load, child: CustomScrollView(slivers: [
    SliverToBoxAdapter(child: topBar()),
    if (history.isNotEmpty) SliverToBoxAdapter(child: section('Continue Watching', catalog.where((e) => history.containsKey(e.id)).toList())),
    if (!loading && error == null) ...[
      SliverToBoxAdapter(child: section('Trending Now', catalog)),
      SliverToBoxAdapter(child: section('Movies', catalog.where((e) => e.type.toLowerCase() == 'movie').toList())),
      SliverToBoxAdapter(child: section('Web Series', catalog.where((e) => e.type.toLowerCase() == 'series').toList())),
      SliverToBoxAdapter(child: section('Anime', catalog.where((e) => e.type.toLowerCase() == 'anime').toList())),
    ],
    if (loading) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator(color: mint)))),
    if (error != null) SliverToBoxAdapter(child: message(error!, true)),
    const SliverToBoxAdapter(child: SizedBox(height: 24)),
  ]));

  Widget topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Row(children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(colors: [blue, mint])),
        child: const Icon(Icons.play_arrow, color: Colors.black, size: 30),
      ),
      const SizedBox(width: 12),
      Expanded(child: InkWell(
        onTap: openSearch,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: const Color(0xFF343034), borderRadius: BorderRadius.circular(13)),
          child: Row(children: [
            const Icon(Icons.search, color: Colors.white70, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(catalog.isNotEmpty ? catalog.first.title : _searchHint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70))),
            const SizedBox(width: 8),
            const Text('Search', style: TextStyle(color: mint, fontWeight: FontWeight.bold)),
          ]),
        ),
      )),
    ]),
  );

  void openSearch() => Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen(catalog: catalogNotifier, onOpen: open)));

  Widget section(String title, List<ContentItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 12, 16, 10), child: Row(children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const Spacer(),
        const Icon(Icons.chevron_right, color: Colors.white54),
      ])),
      SizedBox(height: 205, child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length > 12 ? 12 : items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 11),
        itemBuilder: (_, i) => PosterCard(item: items[i], onTap: () => open(items[i])),
      )),
    ]);
  }

  // ---------------- Me ----------------
  Widget me() {
    final watched = catalog.where((e) => history.containsKey(e.id)).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 28), children: [
      groupPanel([
        meRow(Icons.history, 'Watch History', '', () => collection('Watch History', history.keys.toSet())),
        if (watched.isNotEmpty) Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: SizedBox(height: 112, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: watched.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => historyThumb(watched[i]),
          )),
        ),
        rowDivider(),
        meRow(Icons.bookmark_border, 'My List', '${saved.length}', () => collection('My List', saved)),
        rowDivider(),
        meRow(Icons.live_tv_outlined, 'My Links', '', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalLinksScreen()))),
      ]),
      const SizedBox(height: 14),
      groupPanel([meRow(Icons.settings_outlined, 'Settings', '', settings)]),
    ]);
  }
  Widget historyThumb(ContentItem item) => InkWell(
    onTap: () => open(item),
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(width: 140, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: 140, child: item.posterUrl == null
            ? const PosterFallback()
            : Image.network(item.posterUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const PosterFallback())),
      )),
      const SizedBox(height: 5),
      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
    ])),
  );
  Widget groupPanel(List<Widget> children) => Material(
    color: panel,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
  Widget rowDivider() => const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1, color: Colors.white10));
  Widget meRow(IconData icon, String title, String trailing, VoidCallback tap) => InkWell(
    onTap: tap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18), child: Row(children: [
      Icon(icon, color: Colors.white70, size: 26),
      const SizedBox(width: 14),
      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
      if (trailing.isNotEmpty) Text(trailing, style: const TextStyle(color: muted, fontSize: 15)),
      const SizedBox(width: 6),
      const Icon(Icons.chevron_right, color: Colors.white60),
    ])),
  );

  void settings() => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(mode: watchMode, onMode: (v) async {
    setState(() => watchMode = v);
    final p = await SharedPreferences.getInstance();
    await p.setString('moviebox.watch_mode', v);
  })));
  void collection(String title, Set<String> ids) {
    final list = catalog.where((e) => ids.contains(e.id)).toList();
    Navigator.push(context, MaterialPageRoute(builder: (_) => CollectionPage(title: title, items: list, onOpen: open)));
  }
  void open(ContentItem item) {
    setState(() => history[item.id] = history[item.id] ?? .01);
    persistCollections();
    Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(item: item, isSaved: saved.contains(item.id), onToggleSaved: () => toggleSaved(item))));
  }
  Widget message(String text, bool retry) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off_outlined, size: 42, color: muted),
    const SizedBox(height: 12),
    Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
    if (retry) TextButton.icon(onPressed: load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
  ])));
}

// ---------------- Shared widgets ----------------
class PosterFallback extends StatelessWidget {
  const PosterFallback({super.key});
  @override Widget build(BuildContext context) => Container(color: const Color(0xFF27292E), child: const Center(child: Icon(Icons.movie_outlined, size: 34, color: Colors.white38)));
}

class PosterCard extends StatelessWidget {
  final ContentItem item;
  final VoidCallback onTap;
  const PosterCard({super.key, required this.item, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: SizedBox(width: 124, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 124, child: item.posterUrl == null
        ? const PosterFallback()
        : Image.network(item.posterUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const PosterFallback())))),
    const SizedBox(height: 7),
    Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    Text([if (item.year != null) item.year.toString(), item.type].join(' • '), maxLines: 1, style: const TextStyle(color: muted, fontSize: 10)),
  ])));
}

class GradientSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const GradientSwitch({super.key, required this.value, required this.onChanged});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 52, height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: value ? const LinearGradient(colors: [blue, mint]) : null,
        color: value ? null : Colors.white24,
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
      ),
    ),
  );
}

// ---------------- Search ----------------
class SearchScreen extends StatefulWidget {
  final ValueNotifier<List<ContentItem>> catalog;
  final ValueChanged<ContentItem> onOpen;
  const SearchScreen({super.key, required this.catalog, required this.onOpen});
  @override State<SearchScreen> createState() => _SearchScreenState();
}
class _SearchScreenState extends State<SearchScreen> {
  String query = '', type = 'all';
  List<ContentItem> filter(List<ContentItem> all) => all.where((e) =>
      (type == 'all' || e.type.toLowerCase() == type) &&
      (query.isEmpty || e.title.toLowerCase().contains(query.toLowerCase()))).toList();

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    appBar: AppBar(backgroundColor: bg, title: const Text('Search')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: TextField(
        autofocus: true,
        onChanged: (v) => setState(() => query = v),
        decoration: InputDecoration(
          hintText: 'What do you want to watch?',
          prefixIcon: const Icon(Icons.search),
          filled: true, fillColor: panel,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      )),
      const SizedBox(height: 10),
      SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        chip('All', 'all'), chip('Movies', 'movie'), chip('Series', 'series'), chip('Anime', 'anime'),
      ])),
      Expanded(child: ValueListenableBuilder<List<ContentItem>>(
        valueListenable: widget.catalog,
        builder: (_, all, __) {
          final results = filter(all);
          if (results.isEmpty) return const Center(child: Text('No titles found', style: TextStyle(color: muted)));
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: results.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: .57, crossAxisSpacing: 10, mainAxisSpacing: 14),
            itemBuilder: (_, i) => PosterCard(item: results[i], onTap: () => widget.onOpen(results[i])),
          );
        },
      )),
    ]),
  );
  Widget chip(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ChoiceChip(
      label: Text(label), selected: type == value,
      onSelected: (_) => setState(() => type = value),
      backgroundColor: panel, selectedColor: mint, side: BorderSide.none,
      labelStyle: TextStyle(color: type == value ? Colors.black : Colors.white70, fontWeight: FontWeight.w600),
    ),
  );
}

// ---------------- Collections ----------------
class CollectionPage extends StatelessWidget {
  final String title;final List<ContentItem> items;final ValueChanged<ContentItem> onOpen;
  const CollectionPage({super.key,required this.title,required this.items,required this.onOpen});
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:bg,appBar:AppBar(backgroundColor:bg,title:Text(title)),body:items.isEmpty?const Center(child:Text('Nothing here yet',style:TextStyle(color:muted))):ListView.builder(itemCount:items.length,itemBuilder:(_,i)=>ListTile(onTap:()=>onOpen(items[i]),leading:SizedBox(width:48,child:items[i].posterUrl==null?const Icon(Icons.movie):Image.network(items[i].posterUrl!,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.movie))),title:Text(items[i].title),subtitle:Text(items[i].type,style:const TextStyle(color:muted)),trailing:const Icon(Icons.play_circle_outline))));
}

// ---------------- Settings ----------------
class SettingsPage extends StatefulWidget {
  final String mode;final ValueChanged<String> onMode;
  const SettingsPage({super.key,required this.mode,required this.onMode});
  @override State<SettingsPage> createState()=>_SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage>{
  late String mode;
  bool notifications = true, background = true, mini = true;
  @override void initState(){super.initState();mode=widget.mode;}

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor: bg,
    appBar: AppBar(backgroundColor: bg, centerTitle: true, title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700))),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 12), child: Text('Your app and preferences', style: TextStyle(color: muted))),
      Material(color: panel, borderRadius: BorderRadius.circular(16), clipBehavior: Clip.antiAlias, child: Column(children: [
        row('Notifications', tap: notificationOptions),
        divider(),
        row('Language', tap: languageOptions),
        divider(),
        row('Watch Options', trailing: Text(mode == 'streaming' ? 'Streaming' : 'Download', style: const TextStyle(color: muted)), tap: watchOptions),
        divider(),
        switchRow('Download in background', background, (v) => setState(() => background = v)),
        divider(),
        switchRow('Auto activate Miniplayer', mini, (v) => setState(() => mini = v),
            subtitle: 'When enabled, switching pages during playback will automatically enable Miniplayer.'),
      ])),
    ]),
  );

  Widget divider() => const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1, color: Colors.white10));
  Widget row(String title, {Widget? trailing, VoidCallback? tap}) => InkWell(
    onTap: tap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18), child: Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
      if (trailing != null) ...[trailing, const SizedBox(width: 6)],
      const Icon(Icons.chevron_right, color: Colors.white54),
    ])),
  );
  Widget switchRow(String title, bool value, ValueChanged<bool> onChanged, {String? subtitle}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
        GradientSwitch(value: value, onChanged: onChanged),
      ]),
      if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(subtitle, style: const TextStyle(color: muted, fontSize: 14))),
    ]),
  );

  void notificationOptions() => showModalBottomSheet(context: context, backgroundColor: panel, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => SafeArea(child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    child: Row(children: [
      const Expanded(child: Text('Allow notifications', style: TextStyle(fontSize: 16))),
      GradientSwitch(value: notifications, onChanged: (v) { update(() => notifications = v); setState(() {}); }),
    ]),
  ))));
  void languageOptions()=>showModalBottomSheet(context:context,backgroundColor:panel,builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[for(final lang in ['Device default','English','Hindi','Tamil','Telugu','Malayalam','Kannada','Bengali']) ListTile(title:Text(lang),onTap:()=>Navigator.pop(ctx))])));
  void watchOptions()=>showModalBottomSheet(context:context,backgroundColor:panel,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>Padding(padding:const EdgeInsets.fromLTRB(20,20,20,30),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('Watch Options',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('Choose how videos should open by default.',style:TextStyle(color:muted)),const SizedBox(height:16),
    RadioListTile<String>(value:'streaming',groupValue:mode,activeColor:mint,title:const Text('Streaming'),subtitle:const Text('Play videos online instantly'),onChanged:(v)=>update(()=>mode=v!)),
    RadioListTile<String>(value:'download',groupValue:mode,activeColor:mint,title:const Text('Download'),subtitle:const Text('Download first, then watch offline'),onChanged:(v)=>update(()=>mode=v!)),
    const SizedBox(height:10),SizedBox(width:double.infinity,child:FilledButton(onPressed:(){widget.onMode(mode);setState((){});Navigator.pop(ctx);},child:const Text('Save')))
  ]))));
}
