import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/content_item.dart';
import '../services/catalog_service.dart';
import '../services/site_sync_service.dart';
import 'detail_screen.dart';
import 'personal_links_screen.dart';
import 'site_sync_screen.dart';
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
  List<ContentItem> siteItems = [];
  String? cat; // selected website category (null = All)
  String? fGenre;
  int? fYear;
  int mode = 0; // 0 Home, 1 Movie, 2 TV/Series, 3 Anime
  static const _modes = ['Home', 'Movie', 'TV/Series', 'Anime'];
  bool syncing = false;
  final catalogNotifier = ValueNotifier<List<ContentItem>>([]);
  final Set<String> saved = {};
  final Map<String, double> history = {};

  List<ContentItem> get all => [...siteItems, ...catalog];
  // Newest titles first: the website's latest, or the catalogue's trending list.
  List<ContentItem> get heroItems {
    if (siteItems.isEmpty) return catalog.take(6).toList();
    if (cat != null) return siteItems.where((e) => e.category == cat).take(6).toList();
    final labels = SiteSyncHub.active.map((s) => s.source.label).toList();
    final per = labels.length <= 1 ? 6 : 2;
    final out = <ContentItem>[];
    for (final l in labels) {
      out.addAll(siteItems.where((e) => e.category == l).take(per));
    }
    return out.take(6).toList();
  }

  @override void initState() {
    super.initState();
    restoreLocalData();
    load();
    loadSite();
    SiteSyncService.revision.addListener(siteChanged);
  }
  @override void dispose() {
    SiteSyncService.revision.removeListener(siteChanged);
    catalogNotifier.dispose();
    super.dispose();
  }

  // ---------------- Website sync ----------------
  Future<void> loadSite() async {
    final cached = await SiteSyncHub.cachedItems();
    if (!mounted) return;
    setState(() => siteItems = cached);
    catalogNotifier.value = all;
    await autoSyncIfDue();
  }
  Future<void> siteChanged() async {
    final cached = await SiteSyncHub.cachedItems();
    if (!mounted) return;
    setState(() => siteItems = cached);
    catalogNotifier.value = all;
  }
  Future<void> autoSyncIfDue() async {
    if (syncing || !await SiteSyncHub.shouldAutoSync()) return;
    await runSync();
  }
  Future<void> runSync({bool manual = false}) async {
    if (syncing || SiteSyncHub.isRunning || SiteSyncHub.active.isEmpty) return;
    setState(() => syncing = true);
    final result = await SiteSyncHub.syncAll(force: manual);
    final cached = await SiteSyncHub.cachedItems();
    if (!mounted) return;
    setState(() { syncing = false; siteItems = cached; });
    catalogNotifier.value = all;
    final text = result.error != null
        ? 'Website sync failed: ${result.error}'
        : result.added > 0
            ? '${result.added} new titles added'
            : manual ? 'Already up to date (${result.total} titles)' : null;
    if (text != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

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
  // The catalogue is saved on the phone and reused for 12 hours, so opening
  // the app does not download it again. Pull down to refresh manually.
  static const _catalogKey = 'moviebox.catalog_cache';
  static const _catalogTimeKey = 'moviebox.catalog_time';

  List<ContentItem>? readCatalogCache(SharedPreferences prefs, {bool ignoreAge = false}) {
    try {
      final raw = prefs.getString(_catalogKey);
      final time = DateTime.tryParse(prefs.getString(_catalogTimeKey) ?? '');
      if (raw == null || time == null) return null;
      if (!ignoreAge && DateTime.now().difference(time) > const Duration(hours: 12)) return null;
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => ContentItem.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      return list.isEmpty ? null : list;
    } catch (_) {
      return null;
    }
  }

  Future<void> load({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final cached = readCatalogCache(prefs);
      if (cached != null) {
        if (!mounted) return;
        setState(() { catalog = cached; loading = false; error = null; });
        catalogNotifier.value = all;
        return;
      }
    }
    setState(() { loading = true; error = null; });
    try {
      final data = await (service ??= CatalogService()).loadAll(limit: 150);
      if (!mounted) return;
      if (data.isNotEmpty) {
        await prefs.setString(_catalogKey, jsonEncode(data.map((e) => e.toMap()).toList()));
        await prefs.setString(_catalogTimeKey, DateTime.now().toIso8601String());
      }
      setState(() {
        catalog = data;
        loading = false;
        error = data.isEmpty
            ? 'Catalog is empty or unavailable. Pull down to retry when internet is connected.'
            : null;
      });
      catalogNotifier.value = all;
    } catch (_) {
      if (!mounted) return;
      // Offline: fall back to the last saved catalogue, however old.
      final old = readCatalogCache(prefs, ignoreAge: true);
      setState(() {
        if (old != null) catalog = old;
        loading = false;
        error = old != null ? null : 'Could not load catalogue. Check internet and pull down to retry.';
      });
      catalogNotifier.value = all;
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
  Widget home() => RefreshIndicator(onRefresh: () async { runSync(manual: true); await load(force: true); }, child: CustomScrollView(slivers: [
    SliverToBoxAdapter(child: topBar()),
    SliverToBoxAdapter(child: modeTabs()),
    if (syncing) SliverToBoxAdapter(child: syncBar()),
    if (mode != 0) ...browseSlivers() else ...[
      if (heroItems.isNotEmpty) SliverToBoxAdapter(child: HeroBanner(items: heroItems, onOpen: open)),
      if (SiteSyncHub.active.length > 1) SliverToBoxAdapter(child: categoriesRow()),
      if (history.isNotEmpty) SliverToBoxAdapter(child: section('Continue Watching', all.where((e) => history.containsKey(e.id)).toList())),
      for (final site in SiteSyncHub.active)
        if (cat == null || cat == site.source.label)
          SliverToBoxAdapter(child: section(site.source.label, siteItems.where((e) => e.category == site.source.label).toList())),
      if (!loading && catalog.isNotEmpty && cat == null) ...[
        SliverToBoxAdapter(child: section('Trending Now', catalog)),
        SliverToBoxAdapter(child: section('Movies', catalog.where((e) => e.type.toLowerCase() == 'movie').toList())),
        SliverToBoxAdapter(child: section('Web Series', catalog.where((e) => e.type.toLowerCase() == 'series').toList())),
        SliverToBoxAdapter(child: section('Anime', catalog.where((e) => e.type.toLowerCase() == 'anime').toList())),
      ],
      if (loading && siteItems.isEmpty) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator(color: mint)))),
      if (error != null && all.isEmpty && !syncing) SliverToBoxAdapter(child: message(error!, true)),
    ],
    const SliverToBoxAdapter(child: SizedBox(height: 24)),
  ]));

  // ---------------- Tabs + Movie / TV / Anime browsing with filters ----------------
  Widget modeTabs() => SizedBox(
    height: 46,
    child: Row(children: [
      for (var i = 0; i < _modes.length; i++)
        Expanded(child: InkWell(
          onTap: () => setState(() { mode = i; fGenre = null; fYear = null; }),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_modes[i], style: TextStyle(fontSize: 16, fontWeight: mode == i ? FontWeight.w800 : FontWeight.w500, color: mode == i ? Colors.white : Colors.white60)),
            const SizedBox(height: 5),
            Container(width: 24, height: 3, decoration: BoxDecoration(color: mode == i ? mint : Colors.transparent, borderRadius: BorderRadius.circular(2))),
          ]),
        )),
    ]),
  );

  bool _isAnime(ContentItem e) => e.type.toLowerCase() == 'anime' || e.category == 'Anime';
  List<ContentItem> modeItems() {
    switch (mode) {
      case 1: return all.where((e) => !_isAnime(e) && e.type.toLowerCase() == 'movie').toList();
      case 2: return all.where((e) => !_isAnime(e) && e.type.toLowerCase() == 'series').toList();
      default: return all.where(_isAnime).toList();
    }
  }

  List<Widget> browseSlivers() {
    final base = modeItems();
    final items = base.where((e) =>
        (cat == null || e.category == cat) &&
        (fGenre == null || e.genres.contains(fGenre)) &&
        (fYear == null || e.year == fYear)).toList();
    return [
      SliverToBoxAdapter(child: filterRow(base)),
      if (items.isEmpty) SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.all(40),
        child: Center(child: Text(loading || syncing ? 'Loading titles...' : 'No titles match these filters', style: const TextStyle(color: muted))),
      )),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: .47, crossAxisSpacing: 10, mainAxisSpacing: 14),
          delegate: SliverChildBuilderDelegate(
            (_, i) => BrowseCard(item: items[i], onTap: () => open(items[i])),
            childCount: items.length,
          ),
        ),
      ),
    ];
  }

  Widget filterRow(List<ContentItem> base) {
    final counts = <String, int>{};
    for (final e in base) {
      for (final g in e.genres) { counts[g] = (counts[g] ?? 0) + 1; }
    }
    final genres = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final years = base.map((e) => e.year).whereType<int>().toSet().toList()..sort((a, b) => b.compareTo(a));
    final labels = SiteSyncHub.active.map((s) => s.source.label).toList();
    final any = cat != null || fGenre != null || fYear != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        if (labels.length > 1) filterPill('Category', cat, labels, (v) => cat = v),
        filterPill('Genre', fGenre, genres.take(40).toList(), (v) => fGenre = v),
        filterPill('Year', fYear?.toString(), years.take(60).map((e) => e.toString()).toList(), (v) => fYear = v == null ? null : int.tryParse(v)),
        if (any) IconButton(
          tooltip: 'Clear filters',
          icon: const Icon(Icons.filter_alt_off_outlined),
          onPressed: () => setState(() { cat = null; fGenre = null; fYear = null; }),
        ),
      ])),
    );
  }

  Widget filterPill(String label, String? value, List<String> options, void Function(String?) apply) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: OutlinedButton(
      onPressed: () => pickFilter(label, value, options, apply),
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: value == null ? Colors.white54 : mint),
        foregroundColor: value == null ? Colors.white : mint,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value ?? label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(width: 4),
        const Icon(Icons.keyboard_arrow_down, size: 20),
      ]),
    ),
  );

  void pickFilter(String title, String? value, List<String> options, void Function(String?) apply) {
    showModalBottomSheet(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .6),
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            title: Text('All $title'),
            trailing: value == null ? const Icon(Icons.check, color: mint) : null,
            onTap: () { Navigator.pop(ctx); setState(() => apply(null)); },
          ),
          if (options.isEmpty) const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Nothing to choose yet. Genres and years appear as titles load.', style: TextStyle(color: muted)),
          ),
          for (final o in options)
            ListTile(
              title: Text(o),
              trailing: o == value ? const Icon(Icons.check, color: mint) : null,
              onTap: () { Navigator.pop(ctx); setState(() => apply(o)); },
            ),
        ]),
      )),
    );
  }

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
            Expanded(child: Text(all.isNotEmpty ? all.first.title : _searchHint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70))),
            const SizedBox(width: 8),
            const Text('Search', style: TextStyle(color: mint, fontWeight: FontWeight.bold)),
          ]),
        ),
      )),
    ]),
  );

  Widget categoriesRow() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Padding(padding: EdgeInsets.fromLTRB(18, 8, 16, 2), child: Text('Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
    categoryBar(),
  ]);

  Widget categoryBar() => SizedBox(
    height: 46,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (final label in <String?>[null, ...SiteSyncHub.active.map((s) => s.source.label)])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ChoiceChip(
              label: Text(label ?? 'All'),
              selected: cat == label,
              onSelected: (_) => setState(() => cat = label),
              backgroundColor: panel,
              selectedColor: mint,
              side: BorderSide.none,
              labelStyle: TextStyle(color: cat == label ? Colors.black : Colors.white70, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    ),
  );

  Widget syncBar() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const LinearProgressIndicator(color: mint, backgroundColor: Colors.white12, minHeight: 3),
      const SizedBox(height: 6),
      ValueListenableBuilder<String?>(
        valueListenable: SiteSyncService.progress,
        builder: (_, text, __) => Text(text ?? 'Syncing your website...', style: const TextStyle(color: muted, fontSize: 12)),
      ),
    ]),
  );

  void openSearch() => Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen(catalog: catalogNotifier, onOpen: open)));

  Widget section(String title, List<ContentItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CollectionPage(title: title, items: items, onOpen: open))),
        child: Padding(padding: const EdgeInsets.fromLTRB(18, 12, 16, 10), child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          const Icon(Icons.chevron_right, color: Colors.white54),
        ])),
      ),
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
    final watched = all.where((e) => history.containsKey(e.id)).toList();
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
            : Image.network(
                item.posterUrl!,
                fit: BoxFit.cover,
                cacheWidth: 300,
                loadingBuilder: (_, child, progress) => progress == null ? child : const PosterFallback(),
                errorBuilder: (_, __, ___) => const PosterFallback())),
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
    final list = all.where((e) => ids.contains(e.id)).toList();
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
    if (retry) TextButton.icon(onPressed: () => load(force: true), icon: const Icon(Icons.refresh), label: const Text('Try again')),
  ])));
}

// ---------------- Shared widgets ----------------
class PosterFallback extends StatelessWidget {
  const PosterFallback({super.key});
  @override Widget build(BuildContext context) => Container(color: const Color(0xFF27292E), child: const Center(child: Icon(Icons.movie_outlined, size: 34, color: Colors.white38)));
}

class PosterCard extends StatefulWidget {
  final ContentItem item;
  final VoidCallback onTap;
  const PosterCard({super.key, required this.item, required this.onTap});
  @override State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {

  // Details of a website title are downloaded only while its card is on screen.
  @override void initState() { super.initState(); SiteSyncHub.requestDetails(widget.item); }
  @override void dispose() { SiteSyncHub.cancelDetails(widget.item); super.dispose(); }
  @override Widget build(BuildContext context) {
    final item = widget.item;
    return InkWell(onTap: widget.onTap, borderRadius: BorderRadius.circular(12), child: SizedBox(width: 124, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 124, child: item.posterUrl == null
        ? const PosterFallback()
        : Image.network(
            item.posterUrl!,
            fit: BoxFit.cover,
            cacheWidth: 300,
            loadingBuilder: (_, child, progress) => progress == null ? child : const PosterFallback(),
            errorBuilder: (_, __, ___) => const PosterFallback())))),
    const SizedBox(height: 7),
    Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    Text([if (item.year != null) item.year.toString(), item.type].join(' • '), maxLines: 1, style: const TextStyle(color: muted, fontSize: 10)),
  ])));
  }
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
        row('Website sync', tap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SiteSyncScreen()))),
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


// ---------------- Hero banner + mini cards (newest / trending first) ----------------
class HeroBanner extends StatefulWidget {
  final List<ContentItem> items;
  final ValueChanged<ContentItem> onOpen;
  const HeroBanner({super.key, required this.items, required this.onOpen});
  @override State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final _page = PageController();
  final _strip = ScrollController();
  Timer? _timer;
  int _index = 0;

  @override void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.items.length < 2 || !_page.hasClients) return;
      _page.animateToPage((_index + 1) % widget.items.length,
          duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
    });
  }
  @override void dispose() { _timer?.cancel(); _page.dispose(); _strip.dispose(); super.dispose(); }

  void _changed(int i) {
    setState(() => _index = i);
    if (_strip.hasClients) {
      _strip.animateTo((i * 312.0).clamp(0.0, _strip.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  @override Widget build(BuildContext context) => SizedBox(
    height: 420,
    child: Stack(children: [
      Positioned(top: 0, left: 0, right: 0, height: 390, child: PageView.builder(
        controller: _page,
        itemCount: widget.items.length,
        onPageChanged: _changed,
        itemBuilder: (_, i) => HeroSlide(item: widget.items[i], onOpen: widget.onOpen),
      )),
      Positioned(left: 0, right: 0, bottom: 0, height: 96, child: ListView.builder(
        controller: _strip,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.items.length,
        itemBuilder: (_, i) => MiniCard(item: widget.items[i], selected: i == _index, onOpen: widget.onOpen),
      )),
    ]),
  );
}

class HeroSlide extends StatefulWidget {
  final ContentItem item;
  final ValueChanged<ContentItem> onOpen;
  const HeroSlide({super.key, required this.item, required this.onOpen});
  @override State<HeroSlide> createState() => _HeroSlideState();
}

class _HeroSlideState extends State<HeroSlide> {
  @override void initState() { super.initState(); SiteSyncHub.requestDetails(widget.item); }
  @override void dispose() { SiteSyncHub.cancelDetails(widget.item); super.dispose(); }

  @override Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      onTap: () => widget.onOpen(item),
      child: Stack(fit: StackFit.expand, children: [
        Container(decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF16323A), Color(0xFF2A1F33)]))),
        if (item.posterUrl != null)
          Image.network(
            item.posterUrl!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            cacheWidth: 900,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        if (item.posterUrl == null) Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(item.title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        )),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xFF101114)], stops: [.7, 1]))),
      ]),
    );
  }
}

class MiniCard extends StatefulWidget {
  final ContentItem item;
  final bool selected;
  final ValueChanged<ContentItem> onOpen;
  const MiniCard({super.key, required this.item, required this.selected, required this.onOpen});
  @override State<MiniCard> createState() => _MiniCardState();
}

class _MiniCardState extends State<MiniCard> {
  @override void initState() { super.initState(); SiteSyncHub.requestDetails(widget.item); }
  @override void dispose() { SiteSyncHub.cancelDetails(widget.item); super.dispose(); }

  @override Widget build(BuildContext context) {
    final item = widget.item;
    final meta = [if (item.year != null) item.year.toString(), if (item.category != null) item.category!, if (item.category == null) item.type].join('  |  ');
    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: const Color(0xEE1D1F23),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: widget.selected ? mint : Colors.transparent, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onOpen(item),
          child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 50, height: 74, child: item.posterUrl == null
                  ? const PosterFallback()
                  : Image.network(item.posterUrl!, fit: BoxFit.cover, cacheWidth: 150, errorBuilder: (_, __, ___) => const PosterFallback())),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 13)),
            ])),
            const SizedBox(width: 8),
            Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: mint, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow, color: Colors.black, size: 28),
            ),
          ])),
        ),
      ),
    );
  }
}

// ---------------- Grid card for Movie / TV / Anime browsing ----------------
class BrowseCard extends StatefulWidget {
  final ContentItem item;
  final VoidCallback onTap;
  const BrowseCard({super.key, required this.item, required this.onTap});
  @override State<BrowseCard> createState() => _BrowseCardState();
}

class _BrowseCardState extends State<BrowseCard> {
  @override void initState() { super.initState(); SiteSyncHub.requestDetails(widget.item); }
  @override void dispose() { SiteSyncHub.cancelDetails(widget.item); super.dispose(); }

  @override Widget build(BuildContext context) {
    final item = widget.item;
    final sub = item.genres.isNotEmpty
        ? item.genres.take(3).join(', ')
        : [item.type, if (item.year != null) item.year.toString()].join(' \u2022 ');
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(aspectRatio: 2 / 3, child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(fit: StackFit.expand, children: [
            item.posterUrl == null
                ? const PosterFallback()
                : Image.network(
                    item.posterUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    loadingBuilder: (_, child, progress) => progress == null ? child : const PosterFallback(),
                    errorBuilder: (_, __, ___) => const PosterFallback()),
            if (item.language != null) Positioned(top: 0, right: 0, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: const BoxDecoration(color: Color(0xCC1D1F23), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(8))),
              child: Text(item.language!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            )),
            if (item.rating != null) Positioned(right: 8, bottom: 6, child: Text(
              item.rating!.toStringAsFixed(1),
              style: const TextStyle(color: Color(0xFFF2C94C), fontWeight: FontWeight.w800, fontSize: 17, shadows: [Shadow(blurRadius: 5)]),
            )),
          ]),
        )),
        const SizedBox(height: 7),
        Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.2)),
        const SizedBox(height: 2),
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 12)),
      ]),
    );
  }
}
