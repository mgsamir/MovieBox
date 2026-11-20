import 'package:flutter/material.dart';

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
  CatalogService? _catalogService;
  int _tab = 0;
  String _query = '';
  String _selectedType = 'all';
  List<ContentItem> _catalog = [];
  bool _loadingCatalog = true;
  String? _catalogError;

  @override
  void initState() {
    super.initState();
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
      final items = await (_catalogService ??= CatalogService()).loadAll(limit: 150);
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

  @override
  Widget build(BuildContext context) {
    final pages = [_home(), _downloads(), _settings()];
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
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      'Discover your next favourite',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
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
