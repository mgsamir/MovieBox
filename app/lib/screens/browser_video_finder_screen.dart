import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/download_service.dart';
import 'player_screen.dart';

const _bg = Color(0xFF101114), _mint = Color(0xFF22D6A0);

/// Finds the real video file of a web page.
///
/// With [auto] set to 'download' or 'play' the page is opened invisibly: the
/// video is found, then downloaded or played without showing a browser. The
/// page only becomes visible if the video cannot be found automatically, so
/// the user can press play on it themselves.
class BrowserVideoFinderScreen extends StatefulWidget {
  final String pageUrl;
  final String title;
  final String? auto; // 'download', 'play' or null (manual browser)
  const BrowserVideoFinderScreen({super.key, required this.pageUrl, required this.title, this.auto});

  @override
  State<BrowserVideoFinderScreen> createState() => _BrowserVideoFinderScreenState();
}

class _BrowserVideoFinderScreenState extends State<BrowserVideoFinderScreen> {
  late final WebViewController _controller;
  Timer? _timer, _stuckTimer, _hlsTimer;
  final Set<String> _sources = {};
  bool _loading = true;
  String? _error;
  bool _manual = false; // page shown to the user
  bool _done = false;
  bool _stuck = false;
  bool _hlsOnly = false;
  int _scans = 0;

  bool get _auto => widget.auto != null;
  bool get _showPage => !_auto || _manual;

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

  // Presses the page's own play button so the stream request starts.
  static const _kickJs = r'''
(() => {
 document.querySelectorAll('video').forEach(v => {
   try { v.muted = true; const p = v.play(); if (p && p.catch) p.catch(() => {}); } catch (_) {}
 });
 ['.vjs-big-play-button', '.jw-icon-display', '.jw-display-icon-container',
  'button[aria-label*="Play" i]', '.plyr__control--overlaid', '.play-button', '.btn-play',
  '[class*="play-btn"]', '[class*="playbtn"]', '[id*="play-btn"]'
 ].forEach(sel => document.querySelectorAll(sel).forEach(e => { try { e.click(); } catch (_) {} }));
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
          _maybeAuto();
        } catch (_) {}
      })
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          // While hidden, never let the page send us to another site (ads/pop-ups).
          if (_auto && !_manual && request.isMainFrame) {
            final a = Uri.tryParse(request.url), b = Uri.tryParse(widget.pageUrl);
            if (a != null && b != null && a.host != b.host) return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (_) { if (mounted) setState(() => _loading = true); },
        onPageFinished: (_) { if (mounted) setState(() => _loading = false); _scan(); },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) setState(() => _error = e.description);
        },
      ));
    _open();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _scan());
    if (_auto) {
      _stuckTimer = Timer(const Duration(seconds: 25), () {
        if (mounted && !_done && _sources.isEmpty) setState(() => _stuck = true);
      });
      _hlsTimer = Timer(const Duration(seconds: 8), _maybeAuto);
    }
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
    try {
      await _controller.runJavaScript(_scanJs);
      if (_auto && !_done && _scans++ % 2 == 0) await _controller.runJavaScript(_kickJs);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- automatic
  bool _isHls(String url) => url.toLowerCase().contains('.m3u8');

  void _maybeAuto() {
    if (!_auto || _done || !mounted || _sources.isEmpty) return;
    final files = _sources.where((u) => !_isHls(u)).toList();
    if (widget.auto == 'download') {
      if (files.isNotEmpty) {
        _autoDownload(files.first);
      } else if (_hlsTimer != null && !_hlsTimer!.isActive && !_hlsOnly) {
        setState(() => _hlsOnly = true); // only a stream was found
      }
    } else {
      _autoPlay(files.isNotEmpty ? files.first : _sources.first);
    }
  }

  Future<void> _autoDownload(String url) async {
    _done = true;
    try {
      await DownloadService.instance.download(title: widget.title, url: url);
      if (mounted) Navigator.pop(context, 'downloading');
    } catch (_) {
      _done = false;
      if (mounted) setState(() => _error = 'Could not start the download.');
    }
  }

  void _autoPlay(String url) {
    _done = true;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PlayerScreen(url: url)));
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
  void dispose() {
    _timer?.cancel();
    _stuckTimer?.cancel();
    _hlsTimer?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------- views
  String _statusText() {
    if (_error != null) return _error!;
    if (_hlsOnly) return 'This video is a stream (HLS), so offline download is not supported yet. You can still watch it.';
    if (_stuck) return 'The video could not be found automatically.';
    return widget.auto == 'download' ? 'Finding the video to download...' : 'Finding the video...';
  }

  Widget _autoView() {
    final failed = _error != null || _stuck || _hlsOnly;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Stack(children: [
        // The page loads here, hidden behind the opaque status view.
        Positioned(left: 0, top: 0, width: 360, height: 640, child: WebViewWidget(controller: _controller)),
        Positioned.fill(child: Container(
          color: _bg,
          child: Center(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!failed) const CircularProgressIndicator(color: _mint),
              if (failed) Icon(_hlsOnly ? Icons.stream : Icons.error_outline, size: 44, color: Colors.white54),
              const SizedBox(height: 20),
              Text(_statusText(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 20),
              if (_hlsOnly) FilledButton(
                onPressed: () => _autoPlay(_sources.first),
                style: FilledButton.styleFrom(backgroundColor: _mint, foregroundColor: Colors.black),
                child: const Text('Watch instead'),
              ),
              if (failed && !_hlsOnly) FilledButton(
                onPressed: () => setState(() => _manual = true),
                style: FilledButton.styleFrom(backgroundColor: _mint, foregroundColor: Colors.black),
                child: const Text('Open the page and press play'),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ]),
          )),
        )),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_showPage) return _autoView();
    final items = _sources.toList();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(onPressed: _scan, icon: const Icon(Icons.refresh), tooltip: 'Scan page')],
      ),
      body: Column(children: [
        if (_loading) const LinearProgressIndicator(color: _mint),
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
              leading: const Icon(Icons.video_library, color: _mint),
              title: Text('Detected video sources: ${items.length}'),
              trailing: TextButton(onPressed: _scan, child: const Text('SCAN')),
              subtitle: Text(_auto
                  ? 'Press play on the page. The video will be picked up automatically.'
                  : 'Play the video on the page, then the source appears here.'),
            ),
            if (items.isNotEmpty)
              Flexible(child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final url = items[index];
                  final uri = Uri.tryParse(url);
                  final label = uri == null ? url : uri.host + (uri.pathSegments.isEmpty ? '' : '/${uri.pathSegments.last}');
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.movie, color: _mint),
                    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_isHls(url) ? 'HLS stream' : 'Video file'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!_isHls(url))
                        IconButton(
                          tooltip: 'Download',
                          icon: const Icon(Icons.download, color: _mint),
                          onPressed: () => _download(url),
                        ),
                      IconButton(
                        tooltip: 'Play',
                        icon: const Icon(Icons.play_arrow, color: _mint),
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
