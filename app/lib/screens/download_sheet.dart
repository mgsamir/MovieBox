import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/media_options.dart';

const _bg = Color(0xFF101114), _panel = Color(0xFF1D1F23), _mint = Color(0xFF22D6A0), _blue = Color(0xFF21B7F3), _muted = Color(0xFF9A9DA5);

/// Bottom sheet that lists the available languages and qualities of a title.
Future<void> showDownloadSheet(
  BuildContext context, {
  required String title,
  required List<MediaOption> options,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _DownloadSheet(title: title, options: options),
  );
}

class _DownloadSheet extends StatefulWidget {
  final String title;
  final List<MediaOption> options;
  const _DownloadSheet({required this.title, required this.options});
  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  late final List<String> languages;
  late String language;
  final Set<String> selected = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    languages = <String>{for (final o in widget.options) o.language}.toList();
    // Start on a language that has at least one downloadable file.
    language = languages.firstWhere(
      (l) => widget.options.any((o) => o.language == l && !o.isStream),
      orElse: () => languages.first,
    );
    _preselect();
  }

  List<MediaOption> get current => widget.options.where((o) => o.language == language).toList();
  List<MediaOption> get downloadable => current.where((o) => !o.isStream).toList();

  void _preselect() {
    selected.clear();
    final list = downloadable;
    if (list.isEmpty) return;
    final best = list.firstWhere((o) => o.height == 1080, orElse: () => list[list.length ~/ 2]);
    selected.add(best.url);
  }

  int get totalBytes => downloadable.where((o) => selected.contains(o.url)).fold(0, (a, o) => a + (o.bytes ?? 0));
  bool get allSelected => downloadable.isNotEmpty && downloadable.every((o) => selected.contains(o.url));

  Future<void> _download() async {
    final chosen = downloadable.where((o) => selected.contains(o.url)).toList();
    if (chosen.isEmpty || busy) return;
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);
    var started = 0;
    for (final o in chosen) {
      final tag = languages.length > 1 ? '${o.quality}, ${o.language}' : o.quality;
      try {
        await DownloadService.instance.download(title: '${widget.title} [$tag]', url: o.url);
        started++;
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(started == 0
            ? 'Could not start the download.'
            : '$started download${started == 1 ? '' : 's'} started. Check the Downloads tab.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final list = current;
    final total = totalBytes;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .72,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(children: [
              const Expanded(child: Text('Download', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Text('Resources', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: language,
                    dropdownColor: _panel,
                    items: [for (final l in languages) DropdownMenuItem(value: l, child: Text(l))],
                    onChanged: languages.length < 2
                        ? null
                        : (v) => setState(() {
                              language = v!;
                              _preselect();
                            }),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              for (final o in list) _row(o),
              if (list.every((o) => o.isStream))
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('These are streams only. They can be watched but not downloaded.', style: TextStyle(color: _muted)),
                ),
            ]),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              InkWell(
                onTap: () => setState(() {
                  if (allSelected) {
                    selected.clear();
                  } else {
                    selected.addAll(downloadable.map((o) => o.url));
                  }
                }),
                child: Row(children: [
                  _circle(allSelected),
                  const SizedBox(width: 10),
                  const Text('Select All', style: TextStyle(fontSize: 16)),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: selected.isEmpty ? null : _download,
                  child: Opacity(
                    opacity: selected.isEmpty ? .4 : 1,
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(colors: [_blue, _mint]),
                      ),
                      child: busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                          : Text(
                              total > 0 ? 'Download · ${formatBytes(total)}' : 'Download',
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 17),
                            ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _circle(bool on) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? _mint : Colors.transparent,
          border: Border.all(color: on ? _mint : Colors.white54, width: 1.6),
        ),
        child: on ? const Icon(Icons.check, size: 18, color: Colors.black) : null,
      );

  Widget _row(MediaOption o) {
    final on = selected.contains(o.url);
    return InkWell(
      onTap: o.isStream
          ? null
          : () => setState(() {
                if (!selected.add(o.url)) selected.remove(o.url);
              }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          _circle(on),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${o.quality} ${widget.title}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, color: o.isStream ? _muted : Colors.white)),
              const SizedBox(height: 3),
              Text(o.isStream ? 'Stream only, cannot be downloaded' : o.sizeText, style: const TextStyle(color: _muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}
