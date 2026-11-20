import 'package:flutter/material.dart';

import '../models/content_item.dart';
import '../models/season_episode.dart';
import '../services/catalog_service.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final ContentItem item;
  final bool isSaved;
  final VoidCallback? onToggleSaved;

  const DetailScreen({
    super.key,
    required this.item,
    this.isSaved = false,
    this.onToggleSaved,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final CatalogService _catalog = CatalogService();
  List<SeasonItem> _seasons = [];
  List<EpisodeItem> _episodes = [];
  SeasonItem? _selectedSeason;
  bool _loadingSeasons = false;
  bool _loadingEpisodes = false;
  String? _seasonError;

  bool get _isEpisodic {
    final type = widget.item.type.toLowerCase();
    return type == 'series' || type == 'anime' || type == 'web_series';
  }

  @override
  void initState() {
    super.initState();
    if (_isEpisodic) _loadSeasons();
  }

  Future<void> _loadSeasons() async {
    setState(() {
      _loadingSeasons = true;
      _seasonError = null;
    });
    try {
      final seasons = await _catalog.loadSeasons(widget.item.id);
      if (!mounted) return;
      setState(() {
        _seasons = seasons;
        _selectedSeason = seasons.isEmpty ? null : seasons.first;
        _loadingSeasons = false;
      });
      if (_selectedSeason != null) {
        await _loadEpisodes(_selectedSeason!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSeasons = false;
        _seasonError = 'Seasons could not be loaded. Check the catalog setup.';
      });
    }
  }

  Future<void> _loadEpisodes(SeasonItem season) async {
    setState(() {
      _loadingEpisodes = true;
      _episodes = [];
    });
    try {
      final episodes = await _catalog.loadEpisodes(season.id);
      if (!mounted) return;
      setState(() {
        _episodes = episodes;
        _loadingEpisodes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingEpisodes = false;
        _seasonError = 'Episodes could not be loaded. Check the catalog setup.';
      });
    }
  }

  Future<void> _selectSeason(SeasonItem? season) async {
    if (season == null) return;
    setState(() {
      _selectedSeason = season;
      _seasonError = null;
    });
    await _loadEpisodes(season);
  }

  void _play(String url) {
    if (!url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This episode does not have a valid HTTPS video link.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final metadata = <String>[
      if (item.year != null) item.year.toString(),
      if (item.type.isNotEmpty) item.type[0].toUpperCase() + item.type.substring(1),
      if (item.rating != null) '★ \${item.rating!.toStringAsFixed(1)}',
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF101114),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101114),
        title: const Text('Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (item.posterUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                item.posterUrl!,
                height: 360,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: widget.isSaved ? 'Remove from My List' : 'Add to My List',
                onPressed: widget.onToggleSaved,
                icon: Icon(
                  widget.isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: widget.isSaved ? const Color(0xFF22D6A0) : null,
                ),
              ),
            ],
          ),
          if (metadata.isNotEmpty)
            Text(metadata.join('  •  '), style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF173D35),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Text(
              'HINDI DUBBED',
              style: TextStyle(
                color: Color(0xFF62E8BD),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          if (item.synopsis != null) ...[
            const SizedBox(height: 16),
            Text(item.synopsis!),
          ],
          if (_isEpisodic) ...[
            const SizedBox(height: 26),
            const Text('Seasons & Episodes',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (_loadingSeasons)
              const Center(child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Color(0xFF22D6A0)),
              ))
            else if (_seasonError != null)
              Text(_seasonError!, style: const TextStyle(color: Colors.orangeAccent))
            else if (_seasons.isEmpty)
              const Text('No seasons added yet.',
                  style: TextStyle(color: Colors.white60))
            else ...[
              DropdownButtonFormField<SeasonItem>(
                value: _selectedSeason,
                dropdownColor: const Color(0xFF1D1F23),
                decoration: InputDecoration(
                  labelText: 'Select season',
                  filled: true,
                  fillColor: const Color(0xFF1D1F23),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _seasons.map((season) => DropdownMenuItem(
                  value: season,
                  child: Text(season.title),
                )).toList(),
                onChanged: _selectSeason,
              ),
              const SizedBox(height: 12),
              if (_loadingEpisodes)
                const Center(child: CircularProgressIndicator(color: Color(0xFF22D6A0)))
              else if (_episodes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No Hindi-dubbed episodes in this season yet.',
                      style: TextStyle(color: Colors.white60)),
                )
              else
                ..._episodes.map(_episodeTile),
            ],
          ] else if (item.videoUrl != null && item.videoUrl!.startsWith('https://')) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _play(item.videoUrl!),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Watch in Hindi'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF22D6A0),
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _episodeTile(EpisodeItem episode) {
    final duration = episode.durationSeconds == null
        ? ''
        : ' • \${(episode.durationSeconds! ~/ 60)} min';
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1F23),
        borderRadius: BorderRadius.circular(13),
      ),
      child: ListTile(
        onTap: episode.videoUrl.isEmpty ? null : () => _play(episode.videoUrl),
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF173D35),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            episode.number.toString().padLeft(2, '0'),
            style: const TextStyle(
              color: Color(0xFF62E8BD),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(episode.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'Hindi Dubbed$duration',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        trailing: const Icon(Icons.play_circle_outline, color: Color(0xFF22D6A0)),
      ),
    );
  }
}
