import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/download_service.dart';
import '../services/video_link_resolver.dart';
import 'player_screen.dart';
import 'browser_video_finder_screen.dart';

const _linksBg = Color(0xFF101114);
const _linksPanel = Color(0xFF1D1F23);
const _linksMint = Color(0xFF22D6A0);
const _linksMuted = Color(0xFF9A9DA5);

class PersonalLinksScreen extends StatefulWidget {
  const PersonalLinksScreen({super.key});

  @override
  State<PersonalLinksScreen> createState() => _PersonalLinksScreenState();
}

class _PersonalLinksScreenState extends State<PersonalLinksScreen> {
  static const _storageKey = 'moviebox.personal_video_links';
  List<Map<String, String>> _links = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final decoded = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
    if (!mounted) return;
    setState(() {
      _links = decoded
          .whereType<Map>()
          .map((entry) => entry.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ))
          .where((entry) =>
              entry['title']?.isNotEmpty == true &&
              entry['url']?.isNotEmpty == true)
          .toList();
      _loading = false;
    });
  }

  Future<void> _saveLinks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_links));
  }

  Future<void> _addLink() async {
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    String type = 'Movie';
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => AlertDialog(
          backgroundColor: _linksPanel,
          title: const Text('Add your video or webpage link'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g. My saved movie',
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Enter a title'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: urlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Video or webpage URL',
                      hintText: 'https://example.com/watch/...',
                    ),
                    validator: (value) {
                      final uri = Uri.tryParse(value?.trim() ?? '');
                      if (uri == null ||
                          uri.scheme != 'https' ||
                          uri.host.isEmpty ||
                          uri.userInfo.isNotEmpty) {
                        return 'Enter a valid HTTPS URL';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      DropdownMenuItem(value: 'Movie', child: Text('Movie')),
                      DropdownMenuItem(
                          value: 'Web Series', child: Text('Web Series')),
                      DropdownMenuItem(value: 'Anime', child: Text('Anime')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (value) =>
                        refreshDialog(() => type = value ?? 'Movie'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'MovieBox checks public webpage video tags and supported metadata for a direct video stream. Sign-in, DRM-protected and unsupported embedded players may not work.',
                    style: TextStyle(color: _linksMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext, {
                  'title': titleController.text.trim(),
                  'url': urlController.text.trim(),
                  'type': type,
                });
              },
              child: const Text('Save link'),
            ),
          ],
        ),
      ),
    );

    titleController.dispose();
    urlController.dispose();

    if (result == null) return;
    setState(() => _links.insert(0, result));
    await _saveLinks();
  }

  Future<void> _deleteLink(int index) async {
    final removed = _links.removeAt(index);
    setState(() {});
    await _saveLinks();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${removed['title']} removed from My Links'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            setState(() => _links.insert(
                index.clamp(0, _links.length).toInt(), removed));
            await _saveLinks();
          },
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _download(Map<String, String> link) async {
    _showMessage('Checking webpage for a video source...');
    ResolvedVideoSource source;
    try {
      source = await VideoLinkResolver.resolve(link['url']!);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Video not found automatically. Opening the page so you can play it there.');
      await _openBrowserFinder(link);
      return;
    }
    try {
      if (!source.canDownload) {
        throw const FormatException(
          'This page provides an HLS stream. Online playback may work, but offline download for this stream format is not supported yet.',
        );
      }
      await DownloadService.instance.download(
        title: link['title'] ?? 'Video',
        url: source.uri.toString(),
      );
      _showMessage('Download started: ${link['title']}');
    } catch (error) {
      _showMessage('Could not download: ${_friendlyError(error)}');
    }
  }

  Future<void> _openBrowserFinder(Map<String, String> link) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserVideoFinderScreen(pageUrl: link['url']!, title: link['title'] ?? 'Video Browser')));
  }

  Future<void> _play(Map<String, String> link) async {
    _showMessage('Finding a playable video on this link...');
    ResolvedVideoSource source;
    try {
      source = await VideoLinkResolver.resolve(link['url']!);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Video not found automatically. Opening the page so you can play it there.');
      await _openBrowserFinder(link);
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(url: source.uri.toString()),
      ),
    );
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    return message.startsWith('FormatException: ')
        ? message.substring('FormatException: '.length)
        : message;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _linksBg,
        appBar: AppBar(
          backgroundColor: _linksBg,
          title: const Text('My Links'),
          actions: [
            IconButton(
              tooltip: 'Add video or webpage link',
              onPressed: _addLink,
              icon: const Icon(Icons.add_link, color: _linksMint),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _linksMint))
            : _links.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.link, color: _linksMint, size: 54),
                          SizedBox(height: 14),
                          Text(
                            'Your personal video links',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add a direct video URL or a webpage that publicly exposes a compatible video source. Your links stay saved on this device.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _linksMuted),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _links.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final link = _links[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: _linksPanel,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF263A36),
                            child: Icon(Icons.play_arrow, color: _linksMint),
                          ),
                          title: Text(
                            link['title'] ?? 'Untitled',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${link['type'] ?? 'Video'} • ${Uri.tryParse(link['url'] ?? '')?.host ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _linksMuted, fontSize: 11),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'play') _play(link);
                              if (value == 'browser') _openBrowserFinder(link);
                              if (value == 'download') _download(link);
                              if (value == 'delete') _deleteLink(index);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'play',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.play_arrow),
                                  title: Text('Find & Play'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'browser',
                                child: ListTile(dense: true, leading: Icon(Icons.travel_explore), title: Text('Open Browser & Find Video')),
                              ),
                              PopupMenuItem(
                                value: 'download',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.download),
                                  title: Text('Find & Download'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Delete'),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _play(link),
                        ),
                      );
                    },
                  ),
      );
}
