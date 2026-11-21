import 'package:flutter/material.dart';

import '../services/site_sync_service.dart';

const _bg = Color(0xFF101114), _panel = Color(0xFF1D1F23), _mint = Color(0xFF22D6A0), _muted = Color(0xFF9A9DA5);

/// Shows the state of the website sync. The website address is never shown.
class SiteSyncScreen extends StatefulWidget {
  const SiteSyncScreen({super.key});
  @override
  State<SiteSyncScreen> createState() => _SiteSyncScreenState();
}

class _SiteSyncScreenState extends State<SiteSyncScreen> {
  final svc = SiteSyncService.instance;
  List<String> log = const [];
  int count = 0, pending = 0;
  DateTime? last;
  bool configured = false;
  bool wasRunning = false;

  @override
  void initState() {
    super.initState();
    svc.revision.addListener(_load);
    svc.progress.addListener(_onProgress);
    _load();
  }

  @override
  void dispose() {
    svc.revision.removeListener(_load);
    svc.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (!mounted) return;
    final running = svc.progress.value != null;
    if (wasRunning && !running) _load();
    wasRunning = running;
    setState(() {});
  }

  Future<void> _load() async {
    final l = await svc.lastLog();
    final c = await svc.cachedCount();
    final ls = await svc.lastSync();
    final p = await svc.pending();
    final u = await svc.savedUrl();
    if (!mounted) return;
    setState(() {
      log = l;
      count = c;
      last = ls;
      pending = p;
      configured = u != null;
    });
  }

  Future<void> _sync({bool reset = false}) async {
    if (reset) await svc.clearCache();
    final result = await svc.sync();
    await _load();
    if (!mounted) return;
    final text = result.error != null
        ? 'Sync failed: ${result.error}'
        : '${result.added} new titles, ${result.total} saved';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _lastText() {
    final l = last;
    if (l == null) return 'Never';
    final t = l.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final running = svc.progress.value != null;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, title: const Text('Website sync')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _line('Website', configured ? 'Connected' : 'Not set up'),
            _line('Titles saved', '$count'),
            _line('Details still to read', '$pending'),
            _line('Last sync', _lastText()),
            if (running) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(color: _mint, backgroundColor: Colors.white12),
              const SizedBox(height: 6),
              Text(svc.progress.value ?? '', style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: running || !configured ? null : () => _sync(),
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
              style: FilledButton.styleFrom(backgroundColor: _mint, foregroundColor: Colors.black),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: running || !configured ? null : () => _sync(reset: true),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _mint,
                side: const BorderSide(color: _mint),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        const Text('Last sync details', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
          child: log.isEmpty
              ? const Text('No sync has run yet.', style: TextStyle(color: _muted))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in log)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(line, style: const TextStyle(color: _muted, fontSize: 12.5)),
                      ),
                  ],
                ),
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
