import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

class PlayerScreen extends StatefulWidget {
  final String? url;
  final String? filePath;

  const PlayerScreen({super.key, this.url, this.filePath})
      : assert(url != null || filePath != null);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  const _SubtitleCue(this.start, this.end, this.text);
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoPlayerController controller;
  final TextEditingController _subtitleUrlController = TextEditingController();
  String? error;
  String? subtitleError;
  List<_SubtitleCue> _subtitleCues = [];
  bool _subtitlesEnabled = true;
  bool _isFullscreen = false;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    controller = widget.filePath != null
        ? VideoPlayerController.file(File(widget.filePath!))
        : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {});
      await controller.play();
      _scheduleControlsHide();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'This video link could not be played.');
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _subtitleUrlController.dispose();
    controller.dispose();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
    super.dispose();
  }

  void _scheduleControlsHide() {
    _hideTimer?.cancel();
    if (!controller.value.isPlaying) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showPlayerControls() {
    setState(() => _showControls = true);
    _scheduleControlsHide();
  }

  Future<void> _togglePlayback() async {
    if (!controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) {
      setState(() => _showControls = true);
      _scheduleControlsHide();
    }
  }

  Future<void> _seekBy(int seconds) async {
    final current = controller.value.position;
    final duration = controller.value.duration;
    final target = current + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > duration ? duration : target);
    await controller.seekTo(clamped);
    _showPlayerControls();
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (mounted) {
      setState(() {
        _isFullscreen = !_isFullscreen;
        _showControls = true;
      });
      _scheduleControlsHide();
    }
  }

  Future<void> _askForSubtitleUrl() async {
    _subtitleUrlController.clear();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF191919),
        title: const Text('Add subtitles', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _subtitleUrlController,
          keyboardType: TextInputType.url,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'https://example.com/subtitles.vtt',
            hintStyle: TextStyle(color: Colors.white54),
            labelText: 'Subtitle file URL (.vtt / .srt)',
            labelStyle: TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _subtitleUrlController.text.trim(),
            ),
            child: const Text('Load'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _loadSubtitles(url);
  }

  Future<void> _loadSubtitles(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      setState(() => subtitleError = 'Please enter a valid HTTPS subtitle URL.');
      return;
    }
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FormatException('Subtitle file could not be opened.');
      }
      if (response.bodyBytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Subtitle file is too large.');
      }
      final parsed = _parseSubtitleFile(response.body);
      if (parsed.isEmpty) {
        throw const FormatException('No readable subtitle cues were found.');
      }
      if (!mounted) return;
      setState(() {
        _subtitleCues = parsed;
        _subtitlesEnabled = true;
        subtitleError = null;
      });
      _showPlayerControls();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded ' + parsed.length.toString() + ' subtitle lines')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => subtitleError = e is FormatException
          ? e.message
          : 'Could not load this subtitle file.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(subtitleError!)),
      );
    }
  }

  List<_SubtitleCue> _parseSubtitleFile(String source) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n\s*\n'));
    final cues = <_SubtitleCue>[];
    final timestampPattern = RegExp(
      r'(?:(\d{2}):)?(\d{2}):(\d{2})[,.](\d{3})',
    );

    Duration? parseTimestamp(String value) {
      final match = timestampPattern.firstMatch(value.trim());
      if (match == null) return null;
      return Duration(
        hours: int.parse(match.group(1) ?? '0'),
        minutes: int.parse(match.group(2)!),
        seconds: int.parse(match.group(3)!),
        milliseconds: int.parse(match.group(4)!),
      );
    }

    for (final block in blocks) {
      final lines = block.split('\n');
      final timingIndex = lines.indexWhere((line) => line.contains('-->'));
      if (timingIndex < 0) continue;
      final timing = lines[timingIndex].split('-->');
      if (timing.length != 2) continue;
      final start = parseTimestamp(timing[0]);
      final endText = timing[1].trim().split(RegExp(r'\s+')).first;
      final end = parseTimestamp(endText);
      final textLines = lines.skip(timingIndex + 1).join('\n').trim();
      if (start == null || end == null || end <= start || textLines.isEmpty) {
        continue;
      }
      cues.add(_SubtitleCue(start, end, textLines));
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  String? _subtitleAt(Duration position) {
    if (!_subtitlesEnabled) return null;
    for (final cue in _subtitleCues) {
      if (position >= cue.start && position <= cue.end) return cue.text;
    }
    return null;
  }

  String _formatTime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return hours.toString() + ':' + minutes + ':' + seconds;
    }
    return duration.inMinutes.toString() + ':' + seconds;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('Now Playing'),
              actions: [
                IconButton(
                  tooltip: 'Fullscreen',
                  onPressed: _toggleFullscreen,
                  icon: const Icon(Icons.fullscreen),
                ),
              ],
            ),
      body: Center(
        child: error != null
            ? Text(error!, style: const TextStyle(color: Colors.white70))
            : !controller.value.isInitialized
                ? const CircularProgressIndicator(color: Colors.white)
                : ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, child) {
                      final subtitle = _subtitleAt(value.position);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _showPlayerControls,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Center(
                              child: AspectRatio(
                                aspectRatio: value.aspectRatio > 0
                                    ? value.aspectRatio
                                    : 16 / 9,
                                child: VideoPlayer(controller),
                              ),
                            ),
                            if (subtitle != null)
                              Positioned(
                                left: 20,
                                right: 20,
                                bottom: _showControls ? 112 : 30,
                                child: IgnorePointer(
                                  child: Text(
                                    subtitle,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 5,
                                          offset: Offset(1, 2),
                                        ),
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 9,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (_showControls)
                              Positioned.fill(
                                child: Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0x99000000),
                                        Colors.transparent,
                                        Color(0xCC000000),
                                      ],
                                      stops: [0, 0.42, 1],
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          if (_isFullscreen)
                                            IconButton(
                                              onPressed: _toggleFullscreen,
                                              color: Colors.white,
                                              icon: const Icon(Icons.arrow_back),
                                            ),
                                          const Spacer(),
                                          PopupMenuButton<String>(
                                            tooltip: 'Subtitles',
                                            icon: const Icon(
                                              Icons.subtitles,
                                              color: Colors.white,
                                            ),
                                            color: const Color(0xFF242424),
                                            onSelected: (choice) {
                                              if (choice == 'add') {
                                                _askForSubtitleUrl();
                                              } else if (choice == 'off') {
                                                setState(() => _subtitlesEnabled = false);
                                              } else if (choice == 'on') {
                                                setState(() => _subtitlesEnabled = true);
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'on',
                                                child: Text('Subtitles on'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'off',
                                                child: Text('Subtitles off'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'add',
                                                child: Text('Add subtitle URL'),
                                              ),
                                            ],
                                          ),
                                          IconButton(
                                            tooltip: 'Fullscreen',
                                            onPressed: _toggleFullscreen,
                                            color: Colors.white,
                                            icon: Icon(_isFullscreen
                                                ? Icons.fullscreen_exit
                                                : Icons.fullscreen),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            tooltip: 'Back 10 seconds',
                                            onPressed: () => _seekBy(-10),
                                            color: Colors.white,
                                            iconSize: 34,
                                            icon: const Icon(Icons.replay_10),
                                          ),
                                          const SizedBox(width: 24),
                                          IconButton(
                                            tooltip: value.isPlaying ? 'Pause' : 'Play',
                                            onPressed: _togglePlayback,
                                            color: Colors.white,
                                            iconSize: 58,
                                            icon: Icon(value.isPlaying
                                                ? Icons.pause_circle_filled
                                                : Icons.play_circle_fill),
                                          ),
                                          const SizedBox(width: 24),
                                          IconButton(
                                            tooltip: 'Forward 10 seconds',
                                            onPressed: () => _seekBy(10),
                                            color: Colors.white,
                                            iconSize: 34,
                                            icon: const Icon(Icons.forward_10),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                                        child: Column(
                                          children: [
                                            SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                trackHeight: 3,
                                                thumbShape: const RoundSliderThumbShape(
                                                  enabledThumbRadius: 6,
                                                ),
                                              ),
                                              child: Slider(
                                                min: 0,
                                                max: value.duration.inMilliseconds
                                                            .toDouble() >
                                                        0
                                                    ? value.duration.inMilliseconds.toDouble()
                                                    : 1,
                                                value: value.position.inMilliseconds
                                                    .toDouble()
                                                    .clamp(
                                                      0,
                                                      value.duration.inMilliseconds
                                                                  .toDouble() >
                                                              0
                                                          ? value.duration.inMilliseconds.toDouble()
                                                          : 1,
                                                    ),
                                                activeColor: Colors.white,
                                                inactiveColor: Colors.white38,
                                                onChanged: (milliseconds) {
                                                  controller.seekTo(Duration(
                                                    milliseconds: milliseconds.round(),
                                                  ));
                                                },
                                                onChangeStart: (_) => _hideTimer?.cancel(),
                                                onChangeEnd: (_) => _scheduleControlsHide(),
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  _formatTime(value.position),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const Spacer(),
                                                if (_subtitleCues.isNotEmpty)
                                                  Text(
                                                    _subtitlesEnabled ? 'CC ON' : 'CC OFF',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                const Spacer(),
                                                Text(
                                                  _formatTime(value.duration),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (subtitleError != null && _showControls)
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 8,
                                child: Text(
                                  subtitleError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
