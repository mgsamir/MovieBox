import 'package:flutter/material.dart';

import '../services/site_sync_service.dart';

const _bg = Color(0xFF101114), _panel = Color(0xFF1D1F23), _mint = Color(0xFF22D6A0), _muted = Color(0xFF9A9DA5);

class _Info {
  final SiteSyncService svc;
  final int count, known;
  final DateTime? last;
  final List<String> log;
  const _Info(this.svc, this.count, this.known, this.last, this.log);
}

/// Shows the state of the website sync. Website addresses are never shown.
class SiteSyncScreen extends StatefulWidget {
  const SiteSyncScreen({super.key});
  @override
  State<SiteSyncScreen> createState() => _SiteSyncScreenState();
}

class _SiteSyncScreenState extends State<SiteSyncScreen> {
  List<_Info> infos = const [];
  bool wasRunning = false;

  @override
  void initState() {
    super.initState();
    SiteSyncService.revision.addListener(_load);
    SiteSyncService.progress.addListener(_onProgress);
    _load();
  }

  @override
  void dispose() {
    SiteSyncService.revision.removeListener(_load);
    SiteSyncService.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (!mounted) return;
    final running = SiteSyncService.progress.value != null;
    if (wasRunning && !running) _load();
    wasRunning = running;
    setState(() {});
  }

  Future<void> _load() async {
    final list = <_Info>[];
    for (final svc in SiteSyncHub.active) {
      final count = await svc.cachedCount();
      list.add(_Info(svc, count, svc.knownCount, await svc.lastSync(), await svc.lastLog()));
    }
    if (!mounted) return;
    setState(() => infos = list);
  }

  Future<void> _sync({bool reset = false}) async {
    if (reset) {
      for (final svc in SiteSyncHub.active) {
        await svc.clearCache();
      }
    }
    final result = await SiteSyncHub.syncAll(force: true);
    await _load();
    if (!mounted) return;
    final text = result.error != null
        ? 'Sync problem: ${result.error}'
        : '${result.added} new titles, ${result.total} saved';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _lastText(DateTime? l) {
    if (l == null) return 'Never';
    final t = l.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final running = SiteSyncService.progress.value != null;
    final none = SiteSyncHub.active.isEmpty;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, title: const Text('Website sync')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (running)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const LinearProgressIndicator(color: _mint, backgroundColor: Colors.white12),
              const SizedBox(height: 6),
              Text(SiteSyncService.progress.value ?? '', style: const TextStyle(color: _muted, fontSize: 12)),
            ]),
          ),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: running || none ? null : () => _sync(),
              icon: const Icon(Icons.sync),
              label: const Text('Sync all'),
              style: FilledButton.styleFrom(backgroundColor: _mint, foregroundColor: Colors.black),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: running || none ? null : () => _sync(reset: true),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset all'),
              style: OutlinedButton.styleFrom(foregroundColor: _mint, side: const BorderSide(color: _mint)),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        if (none) const Text('No website is set up yet.', style: TextStyle(color: _muted)),
        for (final i in infos)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.svc.source.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _line('Titles saved', '${i.count}'),
              _line('Details loaded (as you scroll)', '${i.known}'),
              _line('Last sync', _lastText(i.last)),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Last sync details', style: TextStyle(fontSize: 13, color: _muted)),
                  children: [
                    if (i.log.isEmpty)
                      const Align(alignment: Alignment.centerLeft, child: Text('No sync has run yet.', style: TextStyle(color: _muted)))
                    else
                      for (final line in i.log)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(line, style: const TextStyle(color: _muted, fontSize: 12.5)),
                          ),
                        ),
                  ],
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _line(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(a, style: const TextStyle(color: _muted))),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}
