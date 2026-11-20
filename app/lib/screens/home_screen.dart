import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _bg = Color(0xFF09090F);
const _panel = Color(0xFF191925);
const _accent = Color(0xFFB18CFF);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String _query = '';
  List<String> _sources = [];
  bool _loadingSources = true;
  static const _titles = [
    ('Interstellar', 'Movie · Sci-Fi · 2014', 'PLAY + DOWNLOAD'),
    ('The Silent Sea', 'Series · Sci-Fi · 2021', 'PLAY + DOWNLOAD'),
    ('Your Name', 'Anime · Romance · 2016', 'DOWNLOAD ONLY'),
    ('Planet Earth', 'Series · Documentary · 2006', 'PLAY ONLY'),
  ];

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sources = prefs.getStringList('movie_box_sources') ?? [];
      _loadingSources = false;
    });
  }

  Future<void> _addSource() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Add website link'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'https://example.com',
            helperText: 'Add a website you are allowed to access',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;
    final parsed = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    if (parsed == null || !parsed.hasAuthority || !['http', 'https'].contains(parsed.scheme)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid website URL.')));
      return;
    }
    final normalized = parsed.toString();
    if (_sources.contains(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This website is already saved.')));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final updated = [..._sources, normalized];
    await prefs.setStringList('movie_box_sources', updated);
    if (!mounted) return;
    setState(() => _sources = updated);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Website saved on this device.')));
  }

  Future<void> _removeSource(String url) async {
    final updated = _sources.where((item) => item != url).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('movie_box_sources', updated);
    if (mounted) setState(() => _sources = updated);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_home(), _downloads(), _sourcesPage(), _settings()];
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF12121B),
        indicatorColor: const Color(0xFF6C45C8).withValues(alpha: .25),
        selectedIndex: _tab,
        onDestinationSelected: (v) => setState(() => _tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
          NavigationDestination(icon: Icon(Icons.link), label: 'Sources'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _home() {
    final filtered = _titles.where((e) => e.$1.toLowerCase().contains(_query.toLowerCase())).toList();
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Row(children: [
          const Icon(Icons.movie_creation_rounded, color: _accent, size: 30),
          const SizedBox(width: 9),
          const Text('Movie Box', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          const Spacer(),
          IconButton(onPressed: _addSource, icon: const Icon(Icons.add_link, color: _accent)),
        ]),
      )),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(hintText: 'Search movies, series, anime...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: _panel, contentPadding: const EdgeInsets.symmetric(vertical: 2), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
        ),
      )),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          height: 178,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFF39205F), Color(0xFF171725), Color(0xFF101018)])),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('YOUR PERSONAL LIBRARY', style: TextStyle(color: Color(0xFFC8B1FF), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            const Spacer(),
            const Text('Movies. Series. Anime.', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text('Your saved websites in one place', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Spacer(),
            Align(alignment: Alignment.bottomRight, child: FilledButton.tonalIcon(onPressed: _addSource, icon: const Icon(Icons.add, size: 17), label: const Text('Add source'))),
          ]),
        ),
      )),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
        child: Row(children: [const Text('Discover', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)), const Spacer(), Text('${filtered.length} demo titles', style: const TextStyle(color: Colors.white54, fontSize: 12))]),
      )),
      SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, i) { final item = filtered[i]; return _MovieCard(item: item, onTap: () => _showDetails(item)); }, childCount: filtered.length),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: .72, crossAxisSpacing: 12, mainAxisSpacing: 14),
      )),
      const SliverToBoxAdapter(child: SizedBox(height: 20)),
    ]);
  }

  Widget _downloads() => _simplePage(Icons.download_done, 'Downloads', 'Offline downloads will be added in a later step.');
  Widget _sourcesPage() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.fromLTRB(20, 22, 12, 8), child: Row(children: [
      const Expanded(child: Text('Website Sources', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold))),
      IconButton(onPressed: _addSource, icon: const Icon(Icons.add_circle, color: _accent, size: 30)),
    ])),
    const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4), child: Text('Save websites here and open them inside Movie Box. This does not automatically extract movie lists or video files.', style: TextStyle(color: Colors.white60))),
    if (_loadingSources) const Expanded(child: Center(child: CircularProgressIndicator()))
    else if (_sources.isEmpty) Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.link, size: 52, color: _accent), const SizedBox(height: 14),
      const Text('No websites added yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), const Text('Tap + to add a website link.', style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 18), FilledButton.icon(onPressed: _addSource, icon: const Icon(Icons.add), label: const Text('Add website')),
    ]))))
    else Expanded(child: ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _sources.length,
      itemBuilder: (context, i) {
        final url = _sources[i];
        final uri = Uri.parse(url);
        return Card(color: _panel, child: ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFF302344), child: Icon(Icons.language, color: _accent)),
          title: Text(uri.host, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WebsitePage(url: url))),
          trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'delete') _removeSource(url); }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Remove website'))]),
        ));
      },
    )),
  ]);

  Widget _settings() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 18),
    _setting(Icons.dark_mode_outlined, 'Appearance', 'Dark theme'),
    _setting(Icons.storage_outlined, 'Storage', 'Manage downloaded files'),
    _setting(Icons.info_outline, 'About Movie Box', 'Personal, open-source Android app'),
  ]);

  Widget _simplePage(IconData icon, String title, String subtitle) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 54, color: _accent), const SizedBox(height: 16), Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
  ])));

  Widget _setting(IconData icon, String title, String subtitle) => ListTile(leading: Icon(icon, color: _accent), title: Text(title), subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)));

  void _showDetails((String, String, String) item) {
    showModalBottomSheet(context: context, backgroundColor: _panel, builder: (context) => Padding(padding: const EdgeInsets.all(22), child: Wrap(runSpacing: 12, children: [
      Text(item.$1, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      Text(item.$2, style: const TextStyle(color: Colors.white60)),
      Text('Available actions: ${item.$3}', style: const TextStyle(color: _accent)),
      const Text('These are sample cards. Real source-specific playback and downloads are not connected yet.', style: TextStyle(color: Colors.white54)),
    ])));
  }
}

class WebsitePage extends StatefulWidget {
  final String url;
  const WebsitePage({super.key, required this.url});
  @override
  State<WebsitePage> createState() => _WebsitePageState();
}

class _WebsitePageState extends State<WebsitePage> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) => setState(() => _progress = value),
        onWebResourceError: (error) { if (error.isForMainFrame == true) setState(() => _error = error.description); },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(backgroundColor: _panel, title: Text(Uri.parse(widget.url).host, maxLines: 1, overflow: TextOverflow.ellipsis), actions: [
      IconButton(onPressed: () => _controller.reload(), icon: const Icon(Icons.refresh)),
      IconButton(onPressed: () => _controller.goBack(), icon: const Icon(Icons.arrow_back)),
    ]),
    body: Column(children: [
      if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 2, color: _accent, backgroundColor: _panel),
      if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text('Page error: $_error', style: const TextStyle(color: Colors.orangeAccent))),
      Expanded(child: WebViewWidget(controller: _controller)),
    ]),
  );
}

class _MovieCard extends StatelessWidget {
  final (String, String, String) item;
  final VoidCallback onTap;
  const _MovieCard({required this.item, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: Container(width: double.infinity, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF47316C), Color(0xFF171722)])), child: const Center(child: Icon(Icons.movie_outlined, size: 48, color: Color(0xFFBBA0F4))))),
    const SizedBox(height: 7), Text(item.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
    Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
  ]));
}
