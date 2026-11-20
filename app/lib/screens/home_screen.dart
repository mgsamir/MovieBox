import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config.dart';
import '../models/content_item.dart';
import '../services/catalog_service.dart';
import 'detail_screen.dart';

const _bg = Color(0xFF09090F);
const _panel = Color(0xFF191925);
const _accent = Color(0xFFB18CFF);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _catalogService = CatalogService();
  int _tab = 0;
  String _query = '';
  String _selectedType = 'all';
  List<ContentItem> _catalog = [];
  List<String> _sources = [];
  bool _loadingSources = true;
  bool _loadingCatalog = true;
  String? _catalogError;

  @override
  void initState() {
    super.initState();
    _loadSources();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    if (!AppConfig.hasSupabaseConfig) {
      if (!mounted) return;
      setState(() {
        _loadingCatalog = false;
        _catalogError =
            'Catalog connection is not configured. Add your Supabase URL and anon key to the build settings.';
      });
      return;
    }

    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });

    try {
      final items = await _catalogService.loadAll(limit: 150);
      if (!mounted) return;
      setState(() {
        _catalog = items;
        _loadingCatalog = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCatalog = false;
        _catalogError =
            'Could not load the catalog. Check your connection and Supabase table setup, then try again.';
      });
    }
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
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;

    final parsed = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    if (parsed == null ||
        !parsed.hasAuthority ||
        !['http', 'https'].contains(parsed.scheme)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid website URL.')),
      );
      return;
    }

    final normalized = parsed.toString();
    if (_sources.contains(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This website is already saved.')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final updated = [..._sources, normalized];
    await prefs.setStringList('movie_box_sources', updated);
    if (!mounted) return;
    setState(() => _sources = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Website saved on this device.')),
    );
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
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download),
              label: 'Downloads'),
          NavigationDestination(icon: Icon(Icons.link), label: 'Sources'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }

  Widget _home() {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = _catalog.where((item) {
      final matchesType = _selectedType == 'all' || item.type == _selectedType;
      final matchesQuery = normalizedQuery.isEmpty ||
          item.title.toLowerCase().contains(normalizedQuery);
      return matchesType && matchesQuery;
    }).toList(growable: false);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Row(
              children: [
                const Icon(Icons.movie_creation_rounded,
                    color: _accent, size: 30),
                const SizedBox(width: 9),
                const Text('MovieBox',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2)),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh catalog',
                  onPressed: _loadingCatalog ? null : _loadCatalog,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search movies, series, anime...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: _panel,
                      contentPadding: const EdgeInsets.symmetric(vertical: 2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  width: 52,
                  child: FilledButton(
                    onPressed: _addSource,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Icon(Icons.add_link, size: 25),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF39205F),
                    Color(0xFF171725),
                    Color(0xFF101018)
                  ],
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('YOUR PERSONAL LIBRARY',
                      style: TextStyle(
                          color: Color(0xFFC8B1FF),
                          fontSize: 10,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const Text('Movies. Series. Anime.',
                      style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  const Text('One catalog for all your available languages',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: FilledButton.tonalIcon(
                      onPressed: _addSource,
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('Add source'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
            child: Row(
              children: [
                const Text('Discover',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  _loadingCatalog ? 'Updating...' : '${filtered.length} titles',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                _typeChip('All', 'all'),
                _typeChip('Movies', 'movie'),
                _typeChip('Web Series', 'series'),
                _typeChip('Anime', 'anime'),
              ],
            ),
          ),
        ),
        if (_loadingCatalog)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_catalogError != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _catalogMessage(
              Icons.cloud_off_outlined,
              'Catalog unavailable',
              _catalogError!,
              action: FilledButton.icon(
                onPressed: _loadCatalog,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ),
          )
        else if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _catalogMessage(
              Icons.movie_filter_outlined,
              _query.isEmpty ? 'No titles yet' : 'No matching titles',
              _query.isEmpty
                  ? 'The catalog is connected, but no titles are available in this category yet.'
                  : 'Try another title or choose a different category.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = filtered[index];
                  return _MovieCard(
                    item: item,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetailScreen(item: item),
                      ),
                    ),
                  );
                },
                childCount: filtered.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: .72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }

  Widget _typeChip(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _selectedType == value,
          onSelected: (_) => setState(() => _selectedType = value),
          selectedColor: const Color(0xFF39205F),
          backgroundColor: _panel,
          side: BorderSide.none,
          labelStyle: TextStyle(
            color: _selectedType == value ? Colors.white : Colors.white70,
          ),
        ),
      );

  Widget _catalogMessage(
    IconData icon,
    String title,
    String subtitle, {
    Widget? action,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: _accent),
              const SizedBox(height: 14),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60)),
              if (action != null) ...[
                const SizedBox(height: 16),
                action,
              ],
            ],
          ),
        ),
      );

  Widget _downloads() => _simplePage(
        Icons.download_done,
        'Downloads',
        'Offline downloads will be added in a later step.',
      );

  Widget _sourcesPage() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 12, 8),
            child: Row(
              children: [
                const Expanded(
                    child: Text('Website Sources',
                        style: TextStyle(
                            fontSize: 25, fontWeight: FontWeight.bold))),
                IconButton(
                  onPressed: _addSource,
                  icon: const Icon(Icons.add_circle, color: _accent, size: 30),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'Save websites here and open them inside MovieBox. This does not automatically extract movie lists or video files.',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          if (_loadingSources)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_sources.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link, size: 52, color: _accent),
                      const SizedBox(height: 14),
                      const Text('No websites added yet',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Tap + to add a website link.',
                          style: TextStyle(color: Colors.white60)),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _addSource,
                        icon: const Icon(Icons.add),
                        label: const Text('Add website'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: _sources.length,
                itemBuilder: (context, index) {
                  final url = _sources[index];
                  final uri = Uri.parse(url);
                  return Card(
                    color: _panel,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF302344),
                        child: Icon(Icons.language, color: _accent),
                      ),
                      title: Text(uri.host,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11)),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => WebsitePage(url: url)),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'delete') _removeSource(url);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'delete', child: Text('Remove website')),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      );

  Widget _settings() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Settings',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          _setting(Icons.dark_mode_outlined, 'Appearance', 'Dark theme'),
          _setting(Icons.storage_outlined, 'Storage', 'Manage downloaded files'),
          _setting(Icons.info_outline, 'About MovieBox',
              'Personal Android media library'),
        ],
      );

  Widget _simplePage(IconData icon, String title, String subtitle) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 54, color: _accent),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      );

  Widget _setting(IconData icon, String title, String subtitle) => ListTile(
        leading: Icon(icon, color: _accent),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      );
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
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) => setState(() => _progress = value),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              setState(() => _error = error.description);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _panel,
          title: Text(Uri.parse(widget.url).host,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
                onPressed: () => _controller.reload(),
                icon: const Icon(Icons.refresh)),
            IconButton(
                onPressed: () => _controller.goBack(),
                icon: const Icon(Icons.arrow_back)),
          ],
        ),
        body: Column(
          children: [
            if (_progress < 100)
              LinearProgressIndicator(
                value: _progress / 100,
                minHeight: 2,
                color: _accent,
                backgroundColor: _panel,
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Page error: $_error',
                    style: const TextStyle(color: Colors.orangeAccent)),
              ),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      );
}

class _MovieCard extends StatelessWidget {
  final ContentItem item;
  final VoidCallback onTap;

  const _MovieCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: double.infinity,
                  child: item.posterUrl == null
                      ? const ColoredBox(
                          color: Color(0xFF171722),
                          child: Center(
                            child: Icon(Icons.movie_outlined,
                                size: 48, color: Color(0xFFBBA0F4)),
                          ),
                        )
                      : Image.network(
                          item.posterUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFF171722),
                            child: Center(
                              child: Icon(Icons.broken_image_outlined,
                                  size: 42, color: Colors.white38),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              [
                if (item.type.isNotEmpty) item.type,
                if (item.year != null) item.year.toString(),
                if (item.language != null) item.language!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      );
}
