import 'package:flutter/material.dart';

import '../models/content_item.dart';
import 'player_screen.dart';

class DetailScreen extends StatelessWidget {
  final ContentItem item;

  const DetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final metadata = <String>[
      if (item.year != null) item.year.toString(),
      if (item.type.isNotEmpty) item.type[0].toUpperCase() + item.type.substring(1),
      if (item.language != null) item.language!,
      if (item.rating != null) '★ ${item.rating!.toStringAsFixed(1)}',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
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
          Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
          if (metadata.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(metadata.join('  •  '),
                style: const TextStyle(color: Colors.white60)),
          ],
          if (item.synopsis != null) ...[
            const SizedBox(height: 16),
            Text(item.synopsis!),
          ],
          if (item.videoUrl != null && item.videoUrl!.startsWith('https://')) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(url: item.videoUrl!),
                ),
              ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play authorized video'),
            ),
          ],
          if (item.source != null) ...[
            const SizedBox(height: 16),
            Text('Metadata source: ${item.source}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
