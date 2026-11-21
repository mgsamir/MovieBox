import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/download_service.dart';
import 'player_screen.dart';

class BrowserVideoFinderScreen extends StatefulWidget {
  final String pageUrl;
  final String title;
  const BrowserVideoFinderScreen({super.key, required this.pageUrl, required this.title});

  @override
  State<BrowserVideoFinderScreen> createState() => _BrowserVideoFinderScreenState();
}

class _BrowserVideoFinderScreenState extends State<BrowserVideoFinderScreen> {
  late final WebViewController _controller;
  Timer? _timer;
  final Set<String> _sources = {};
  bool _loading = true;
  String? _error;

  static const _scanJs = r'''
(() => {
 const urls = new Set();
 const add = (v) => {
   if (!v || typeof v !== 'string') return;
   try {
     const u = new URL(v, location.href);
     if ((u.protocol === 'https:' || u.protocol === 'http:') &&
       /\.(mp4|m4v|mov|webm|m3u8)(?:$|[?#])/i.test(u.href)) urls.add(u.href);
   } catch (_) {}
 };
 document.querySelectorAll('video').forEach(v => {
   add(v.currentSrc); add(v.src);
   v.querySelectorAll('source').forEach(s => add(s.src));
 });
 document.querySelectorAll('source[src],video[src]').forEach(e => add(e.src));
 try { performance.getEntriesByType('resource').forEach(e => add(e.name)); } catch (_) {}
 MovieBoxMedia.postMessage(JSON.stringify(Array.from(urls)));
})();
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('MovieBoxMedia', onMessageReceived: (message) {
        try {
          final values = (jsonDecode(message.message) as List).whereType<String>();
          if (!mounted) return;
          setState(() => _sources.addAll(values));
        } catch (_) {}
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) { if (mounted) setState(() => _loading = true); },
        onPageFinished: (_) { if (mounted) setState(() => _loading = false); _scan(); },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) setState(() => _error = e.description);
        },
      ));
    _open();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _scan());
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(widget.pageUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      setState(() { _loading = false; _error = 'Please enter a valid HTTPS URL.'; });
      return;
    }
    try { await _controller.loadRequest(uri); }
    catch (e) { if (mounted) setState(() { _loading = false; _error = e.toString(); }); }
  }

  Future<void> _scan() async {
    try { await _controller.runJavaScript(_scanJs); } catch (_) {}
  }

  Future<void> _download(String url) async {
    try {
      await DownloadService.instance.download(title: widget.title, url: url);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Download started. Check the Downloads tab.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not start the download.')));
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final items = _sources.toList();
    return Scaffold(
      backgroundColor: const Color(0xFF101114),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101114),
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(onPressed: _scan, icon: const Icon(Icons.refresh), tooltip: 'Scan page')],
      ),
      body: Column(children: [
        if (_loading) const LinearProgressIndicator(color: Color(0xFF22D6A0)),
        if (_error != null) Padding(
          padding: const EdgeInsets.all(8),
          child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
        ),
        Expanded(child: WebViewWidget(controller: _controller)),
        Container(
          color: const Color(0xFF1D1F23),
          constraints: const BoxConstraints(maxHeight: 220),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.video_library, color: Color(0xFF22D6A0)),
              title: Text('Detected video sources: ' + items.length.toString()),
              trailing: TextButton(onPressed: _scan, child: const Text('SCAN')),
              subtitle: const Text('Video ko webpage par play karo, phir yahan source dikhega.'),
            ),
            if (items.isNotEmpty)
              Flexible(child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final url = items[index];
                  final uri = Uri.tryParse(url);
                  final label = uri == null ? url : uri.host + (uri.pathSegments.isEmpty ? '' : '/' + uri.pathSegments.last);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.movie, color: Color(0xFF22D6A0)),
                    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(url.toLowerCase().contains('.m3u8') ? 'HLS stream' : 'Video file'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!url.toLowerCase().contains('.m3u8'))
                        IconButton(
                          tooltip: 'Download',
                          icon: const Icon(Icons.download, color: Color(0xFF22D6A0)),
                          onPressed: () => _download(url),
                        ),
                      IconButton(
                        tooltip: 'Play',
                        icon: const Icon(Icons.play_arrow, color: Color(0xFF22D6A0)),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(url: url))),
                      ),
                    ]),
                  );
                },
              )),
          ]),
        ),
      ]),
    );
  }
}
