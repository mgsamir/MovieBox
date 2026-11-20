import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String _query = '';
  static const _titles = [
    ('Interstellar', 'Movie · Sci-Fi · 2014', 'PLAY + DOWNLOAD'),
    ('The Silent Sea', 'Series · Sci-Fi · 2021', 'PLAY + DOWNLOAD'),
    ('Your Name', 'Anime · Romance · 2016', 'DOWNLOAD ONLY'),
    ('Planet Earth', 'Series · Documentary · 2006', 'PLAY ONLY'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [_home(), _downloads(), _sources(), _settings()];
    return Scaffold(
      backgroundColor: const Color(0xFF09090F),
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
          const Icon(Icons.movie_creation_rounded, color: Color(0xFFB18CFF), size: 30),
          const SizedBox(width: 9),
          const Text('MOVIE BOX', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          const Spacer(),
          IconButton(onPressed: () => setState(() => _tab = 2), icon: const Icon(Icons.add_link, color: Color(0xFFB18CFF))),
        ]),
      )),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search movies, series, anime...',
            prefixIcon: const Icon(Icons.search),
            filled: true, fillColor: const Color(0xFF191925),
            contentPadding: const EdgeInsets.symmetric(vertical: 2),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      )),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          height: 178,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [Color(0xFF39205F), Color(0xFF171725), Color(0xFF101018)]),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('YOUR PERSONAL LIBRARY', style: TextStyle(color: Color(0xFFC8B1FF), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            const Spacer(),
            const Text('Movies. Series. Anime.', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text('All your sources in one simple place', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Spacer(),
            Align(alignment: Alignment.bottomRight, child: FilledButton.tonalIcon(
              onPressed: () => setState(() => _tab = 2),
              icon: const Icon(Icons.add, size: 17), label: const Text('Add source'),
            )),
          ]),
        ),
      )),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
        child: Row(children: [
          const Text('Discover', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(filtered.length.toString() + ' titles', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      )),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate((context, i) {
            final item = filtered[i];
            return _MovieCard(item: item, onTap: () => _showDetails(item));
          }, childCount: filtered.length),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: .72, crossAxisSpacing: 12, mainAxisSpacing: 14),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 20)),
    ]);
  }

  Widget _downloads() => _simplePage(Icons.download_done, 'Downloads', 'Your offline movies and episodes will appear here.');
  Widget _sources() => _simplePage(Icons.language, 'Website Sources', 'Add a website you are allowed to access. Automatic catalog reading depends on that site supporting it.');
  Widget _settings() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
    const SizedBox(height: 18),
    _setting(Icons.dark_mode_outlined, 'Appearance', 'Dark theme'),
    _setting(Icons.sync, 'Source sync', 'Manual refresh'),
    _setting(Icons.storage_outlined, 'Storage', 'Manage downloaded files'),
    _setting(Icons.info_outline, 'About Movie Box', 'Personal, open-source Android app'),
    _setting(Icons.code, 'Open-source licenses', 'Third-party notices'),
  ]);

  Widget _simplePage(IconData icon, String title, String subtitle) => Center(child: Padding(
    padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 54, color: const Color(0xFFB18CFF)),
      const SizedBox(height: 16),
      Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
    ]),
  ));

  Widget _setting(IconData icon, String title, String subtitle) => ListTile(
    leading: Icon(icon, color: const Color(0xFFB18CFF)), title: Text(title),
    subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
  );

  void _showDetails((String, String, String) item) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF191925), builder: (context) => Padding(
      padding: const EdgeInsets.all(22), child: Wrap(runSpacing: 12, children: [
        Text(item.$1, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(item.$2, style: const TextStyle(color: Colors.white60)),
        Text('Available actions: ' + item.$3, style: const TextStyle(color: Color(0xFFC8B1FF))),
        const Text('Demo card only. Real source links and downloads will be connected in a later step.', style: TextStyle(color: Colors.white54)),
        Row(children: [
          if (item.$3.contains('PLAY')) Expanded(child: FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.play_arrow), label: const Text('Watch'))),
          if (item.$3.contains('PLAY') && item.$3.contains('DOWNLOAD')) const SizedBox(width: 10),
          if (item.$3.contains('DOWNLOAD')) Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.download), label: const Text('Download'))),
        ]),
      ]),
    ));
  }
}

class _MovieCard extends StatelessWidget {
  final (String, String, String) item;
  final VoidCallback onTap;
  const _MovieCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF47316C), Color(0xFF171722)]),
        ),
        child: const Center(child: Icon(Icons.movie_outlined, size: 48, color: Color(0xFFBBA0F4))),
      )),
      const SizedBox(height: 7),
      Text(item.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
    ]),
  );
}
