import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/video_link_resolver.dart';

const _bg = Color(0xFF101114), _panel = Color(0xFF1D1F23), _mint = Color(0xFF22D6A0), _blue = Color(0xFF21B7F3), _muted = Color(0xFF9A9DA5);

String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return 'Size unknown';
  const mb = 1024 * 1024;
  const gb = mb * 1024;
  return bytes >= gb ? '${(bytes / gb).toStringAsFixed(1)}GB' : '${(bytes / mb).toStringAsFixed(1)}MB';
}

/// Lets the user pick the language and the qualities to download.
Future<void> showDownloadSheet(
  BuildContext context, {
  required String title,
  required List<MediaOption> options,
  String? preferredLanguage,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DownloadSheet(title: title, options: options, preferredLanguage: preferredLanguage),
    );

class _DownloadSheet extends StatefulWidget {
  final String title;
  final List<MediaOption> options;
  final String? preferredLanguage;
  const _DownloadSheet({required this.title, required this.options, this.preferredLanguage});
  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  late final List<String?> languages;
  String? language;
  final Set<String> selected = {};
  bool starting = false;

  @override
  void initState() {
    super.initState();
    languages = <String?>{for (final o in widget.options) o.language}.toList();
    final pref = widget.preferredLanguage?.toLowerCase();
    language = languages.firstWhere(
      (l) => l != null && l.toLowerCase() == pref,
      orElse: () => languages.first,
    );
    _pickDefault();
  }

  List<MediaOption> get visible => widget.options.where((o) => o.language == language).toList();
  List<MediaOption> get downloadable => visible.where((o) => o.canDownload).toList();
  String _languageLabel(String? l) => l == null ? 'Original Audio' : (l == 'English' ? 'English' : '$l dub');

  void _pickDefault() {
    selected.clear();
    final list = downloadable;
    if (list.isEmpty) return;
    final best = list.firstWhere((o) => (o.height ?? 0) <= 1080, orElse: () => list.first);
    selected.add(best.uri.toString());
  }

  int get totalBytes => visible
      .where((o) => selected.contains(o.uri.toString()))
      .fold(0, (sum, o) => sum + (o.sizeBytes ?? 0));

  Future<void> _chooseLanguage() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: _bg,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              const Expanded(child: Text('Select language', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
            ]),
          ),
          for (final l in languages)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
              child: InkWell(
                onTap: () => Navigator.pop(ctx, l ?? ''),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: l == language ? null : _panel,
                    gradient: l == language
                        ? const LinearGradient(colors: [Color(0xFF13334A), Color(0xFF17432E)])
                        : null,
                  ),
                  child: Text(_languageLabel(l),
                      style: TextStyle(fontSize: 17, color: l == language ? _mint : Colors.white70)),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (picked == null) return;
    setState(() {
      language = picked.isEmpty ? null : picked;
      _pickDefault();
    });
  }

  Future<void> _start() async {
    if (starting) return;
    setState(() => starting = true);
    final chosen = visible.where((o) => selected.contains(o.uri.toString())).toList();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var started = 0;
    for (final o in chosen) {
      final suffix = [o.qualityLabel, if (o.language != null) o.language!].join(' ');
      try {
        await DownloadService.instance.download(title: '${widget.title} [$suffix]', url: o.uri.toString());
        started++;
      } catch (_) {}
    }
    nav.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(started == 0
          ? 'Could not start the download.'
          : '$started download${started == 1 ? '' : 's'} started. Check the Downloads tab.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final list = visible;
    final canSelectAll = downloadable.isNotEmpty;
    final allSelected = canSelectAll && downloadable.every((o) => selected.contains(o.uri.toString()));
    final total = totalBytes;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Download', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Resources', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: languages.length > 1 ? _chooseLanguage : null,
                icon: Text(_languageLabel(language), style: const TextStyle(color: Colors.white, fontSize: 15)),
                label: Icon(languages.length > 1 ? Icons.keyboard_arrow_down : null, color: Colors.white70),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final o in list)
                InkWell(
                  onTap: o.canDownload
                      ? () => setState(() {
                            final key = o.uri.toString();
                            if (!selected.remove(key)) selected.add(key);
                          })
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    child: Row(children: [
                      Icon(
                        selected.contains(o.uri.toString()) ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: selected.contains(o.uri.toString())
                            ? _mint
                            : (o.canDownload ? Colors.white54 : Colors.white24),
                        size: 28,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${o.qualityLabel} ${widget.title}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, color: o.canDownload ? Colors.white : Colors.white38)),
                          const SizedBox(height: 3),
                          Text(o.canDownload ? formatBytes(o.sizeBytes) : 'Stream only, cannot be downloaded',
                              style: const TextStyle(color: _muted, fontSize: 13)),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
          const Divider(color: Colors.white12),
          Row(children: [
            InkWell(
              onTap: canSelectAll
                  ? () => setState(() {
                        if (allSelected) {
                          selected.clear();
                        } else {
                          selected.addAll(downloadable.map((o) => o.uri.toString()));
                        }
                      })
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(children: [
                  Icon(allSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: allSelected ? _mint : Colors.white54),
                  const SizedBox(width: 8),
                  const Text('Select All', style: TextStyle(fontSize: 16)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: selected.isEmpty ? .4 : 1,
                child: InkWell(
                  onTap: selected.isEmpty ? null : _start,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(colors: [_blue, _mint]),
                    ),
                    child: Text(
                      total > 0
                          ? 'Download · ${formatBytes(total)}'
                          : 'Download${selected.isEmpty ? '' : ' (${selected.length})'}',
                      style: const TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
