import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadTask {
  final String id, title, url, path, status;
  final int received, total;

  const DownloadTask({
    required this.id,
    required this.title,
    required this.url,
    required this.path,
    required this.status,
    required this.received,
    required this.total,
  });

  double get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : 0;
  bool get isComplete => status == 'completed';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'path': path,
        'status': status,
        'received': received,
        'total': total,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Video',
        url: json['url'] as String? ?? '',
        path: json['path'] as String? ?? '',
        status: json['status'] as String? ?? 'paused',
        received: (json['received'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
      );

  DownloadTask copy({String? status, int? received, int? total}) =>
      DownloadTask(
        id: id,
        title: title,
        url: url,
        path: path,
        status: status ?? this.status,
        received: received ?? this.received,
        total: total ?? this.total,
      );
}

class DownloadService extends ChangeNotifier {
  DownloadService._();

  static final DownloadService instance = DownloadService._();
  static const _key = 'moviebox.offline_downloads';

  final List<DownloadTask> _tasks = [];
  final Map<String, HttpClient> _clients = {};
  final Set<String> _activeIds = {};
  Future<void> _persistQueue = Future<void>.value();
  bool _loaded = false;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List;
        for (final entry in decoded.whereType<Map>()) {
          final task = DownloadTask.fromJson(Map<String, dynamic>.from(entry));
          if (task.id.isEmpty || task.path.isEmpty || task.url.isEmpty) continue;
          var recovered = task;
          if (task.status == 'downloading' || task.status == 'queued') {
            recovered = task.copy(status: 'paused');
          }
          try {
            final file = File(task.path);
            final actualBytes = await file.exists() ? await file.length() : 0;
            if (recovered.status != 'completed') {
              recovered = recovered.copy(received: actualBytes);
              if (recovered.total > 0 && actualBytes >= recovered.total) {
                recovered = recovered.copy(status: 'completed', received: recovered.total);
              }
            } else if (actualBytes == 0 && recovered.received > 0) {
              recovered = recovered.copy(status: 'error', received: 0);
            } else {
              recovered = recovered.copy(received: actualBytes);
            }
          } catch (_) {
            recovered = recovered.copy(status: 'error', received: 0);
          }
          _tasks.add(recovered);
        }
      } catch (_) {
        // Ignore malformed saved state rather than preventing the screen opening.
      }
    }
    _loaded = true;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() {
    // Serialize snapshots so an older async write cannot overwrite newer state.
    _persistQueue = _persistQueue.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(_tasks.map((task) => task.toJson()).toList()),
      );
    });
    return _persistQueue;
  }

  void _replace(DownloadTask task) {
    final index = _tasks.indexWhere((entry) => entry.id == task.id);
    if (index < 0) {
      _tasks.insert(0, task);
    } else {
      _tasks[index] = task;
    }
    notifyListeners();
  }

  Future<void> download({required String title, required String url}) async {
    await load();
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError('A valid HTTPS direct video URL is required.');
    }
    if (_tasks.any((task) => task.url == url && task.isComplete)) return;

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final directory = await getApplicationSupportDirectory();
    final safeTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final lastSegment =
        uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final extension = lastSegment.contains('.')
        ? '.${lastSegment.split('.').last.split('?').first}'
        : '.mp4';
    final path = '${directory.path}/moviebox_${safeTitle}_$id$extension';

    final task = DownloadTask(
      id: id,
      title: title,
      url: url,
      path: path,
      status: 'queued',
      received: 0,
      total: 0,
    );
    _replace(task);
    await _persist();

    // Return immediately so the UI can show "Download started" while bytes
    // are transferred in the background.
    unawaited(_run(task.id));
  }

  Future<void> resume(String id) async {
    await load();
    final index = _tasks.indexWhere((entry) => entry.id == id);
    if (index < 0 || _tasks[index].isComplete || _activeIds.contains(id)) return;
    _replace(_tasks[index].copy(status: 'queued'));
    await _persist();
    unawaited(_run(id));
  }

  Future<void> retry(String id) => resume(id);

  Future<void> pause(String id) async {
    final index = _tasks.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    _replace(_tasks[index].copy(status: 'paused'));
    await _persist();
    _clients[id]?.close(force: true);
  }

  Future<void> delete(String id) async {
    final index = _tasks.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    _clients[id]?.close(force: true);
    final task = _tasks.removeAt(index);
    notifyListeners();
    try {
      final file = File(task.path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A missing or locked cache file should not keep the task in the list.
    }
    await _persist();
  }

  Future<void> _run(String id) async {
    if (!_activeIds.add(id)) return;
    var task = _tasks.firstWhere(
      (entry) => entry.id == id,
      orElse: () => const DownloadTask(
        id: '', title: '', url: '', path: '', status: 'deleted',
        received: 0, total: 0,
      ),
    );
    if (task.id.isEmpty || task.status != 'queued') {
      _activeIds.remove(id);
      return;
    }

    final file = File(task.path);
    HttpClient? client;
    RandomAccessFile? handle;
    try {
      await file.parent.create(recursive: true);
      var offset = await file.exists() ? await file.length() : 0;

      client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
      _clients[id] = client;
      task = task.copy(status: 'downloading', received: offset);
      _replace(task);
      await _persist();

      final request = await client.getUrl(Uri.parse(task.url));
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=' + offset.toString() + '-');
      }
      final response = await request.close();

      if (offset == 0 && response.statusCode != HttpStatus.ok) {
        throw HttpException('Server returned HTTP ' + response.statusCode.toString() + '.');
      }
      if (offset > 0 && response.statusCode == HttpStatus.ok) {
        offset = 0;
        await file.writeAsBytes([], flush: true);
      } else if (offset > 0 && response.statusCode == HttpStatus.partialContent) {
        final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
        final match = contentRange == null
            ? null
            : RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(contentRange);
        if (match == null || int.parse(match.group(1)!) != offset) {
          throw HttpException('Server returned an invalid resume range.');
        }
      } else if (offset > 0) {
        throw HttpException('Server cannot resume this download (HTTP ' +
            response.statusCode.toString() + ').');
      }

      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
      final rangeMatch = contentRange == null
          ? null
          : RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(contentRange);
      final rangeTotal = rangeMatch == null || rangeMatch.group(3) == '*'
          ? 0
          : int.tryParse(rangeMatch.group(3)!) ?? 0;
      final total = rangeTotal > 0
          ? rangeTotal
          : (response.contentLength < 0 ? 0 : offset + response.contentLength);

      task = task.copy(received: offset, total: total);
      _replace(task);
      await _persist();

      handle = await file.open(mode: FileMode.append);
      var lastPersistedBytes = offset;
      await for (final chunk in response) {
        final currentIndex = _tasks.indexWhere((entry) => entry.id == id);
        if (currentIndex < 0 || _tasks[currentIndex].status != 'downloading') {
          break;
        }
        await handle.writeFrom(chunk);
        final size = await file.length();
        task = task.copy(received: size, total: total);
        _replace(task);
        if (size - lastPersistedBytes >= 1024 * 1024) {
          lastPersistedBytes = size;
          await _persist();
        }
      }
      await handle.flush();
      await handle.close();
      handle = null;

      final latestIndex = _tasks.indexWhere((entry) => entry.id == id);
      if (latestIndex >= 0 && _tasks[latestIndex].status == 'downloading') {
        final finalSize = await file.length();
        if (total > 0 && finalSize != total) {
          throw HttpException('Incomplete download: received ' +
              finalSize.toString() + ' of ' + total.toString() + ' bytes.');
        }
        _replace(task.copy(
          status: 'completed',
          received: finalSize,
          total: total > 0 ? total : finalSize,
        ));
        await _persist();
      }
    } catch (_) {
      final index = _tasks.indexWhere((entry) => entry.id == id);
      if (index >= 0 && _tasks[index].status == 'downloading') {
        _replace(_tasks[index].copy(status: 'error'));
        await _persist();
      }
    } finally {
      try {
        await handle?.close();
      } catch (_) {}
      client?.close(force: true);
      _clients.remove(id);
      _activeIds.remove(id);
    }
  }
}
