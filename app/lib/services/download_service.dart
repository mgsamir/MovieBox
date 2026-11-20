import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadTask {
  final String id, title, url, path, status;
  final int received, total;
  const DownloadTask({required this.id,required this.title,required this.url,required this.path,required this.status,required this.received,required this.total});
  double get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : 0;
  bool get isComplete => status == 'completed';
  Map<String,dynamic> toJson()=>{'id':id,'title':title,'url':url,'path':path,'status':status,'received':received,'total':total};
  factory DownloadTask.fromJson(Map<String,dynamic> m)=>DownloadTask(id:m['id']??'',title:m['title']??'Video',url:m['url']??'',path:m['path']??'',status:m['status']??'paused',received:m['received']??0,total:m['total']??0);
  DownloadTask copy({String? status,int? received,int? total})=>DownloadTask(id:id,title:title,url:url,path:path,status:status??this.status,received:received??this.received,total:total??this.total);
}

class DownloadService extends ChangeNotifier {
  DownloadService._();
  static final DownloadService instance = DownloadService._();
  static const _key='moviebox.offline_downloads';
  final List<DownloadTask> _tasks=[];
  final Map<String,HttpClient> _clients={};
  bool _loaded=false;
  List<DownloadTask> get tasks=>List.unmodifiable(_tasks);

  Future<void> load() async {
    if(_loaded)return;
    final prefs=await SharedPreferences.getInstance();
    final raw=prefs.getString(_key);
    if(raw!=null){
      try {
        final decoded=jsonDecode(raw) as List;
        _tasks.addAll(decoded.whereType<Map>().map((e)=>DownloadTask.fromJson(Map<String,dynamic>.from(e))));
        for(var i=0;i<_tasks.length;i++){
          final t=_tasks[i];
          if(t.status=='downloading')_tasks[i]=t.copy(status:'paused');
        }
      } catch (_) {}
    }
    _loaded=true;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString(_key,jsonEncode(_tasks.map((e)=>e.toJson()).toList()));
  }
  void _replace(DownloadTask task){final i=_tasks.indexWhere((e)=>e.id==task.id);if(i<0)_tasks.insert(0,task);else _tasks[i]=task;notifyListeners();}

  Future<void> download({required String title,required String url}) async {
    await load();
    final uri=Uri.tryParse(url);
    if(uri==null||uri.scheme!='https'||uri.host.isEmpty)throw ArgumentError('A valid HTTPS direct video URL is required.');
    final existing=_tasks.where((e)=>e.url==url&&e.isComplete).firstOrNull;
    if(existing!=null)return;
    final id=DateTime.now().microsecondsSinceEpoch.toString();
    final dir=await getApplicationSupportDirectory();
    final safe=title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'),'_');
    final ext=uri.pathSegments.isNotEmpty&&uri.pathSegments.last.contains('.')?'.${uri.pathSegments.last.split('.').last.split('?').first}':'.mp4';
    final path='${dir.path}/moviebox_${safe}_$id$ext';
    final task=DownloadTask(id:id,title:title,url:url,path:path,status:'queued',received:0,total:0);
    _replace(task);await _persist();await _run(task);
  }

  Future<void> resume(String id) async {await load();final t=_tasks.firstWhere((e)=>e.id==id);if(t.status=='completed')return;await _run(t.copy(status:'queued'));}
  Future<void> pause(String id) async {
    final i=_tasks.indexWhere((e)=>e.id==id);if(i<0)return;
    _replace(_tasks[i].copy(status:'paused'));await _persist();
    _clients[id]?.close(force:true);
  }
  Future<void> delete(String id) async {
    final i=_tasks.indexWhere((e)=>e.id==id);if(i<0)return;
    _clients[id]?.close(force:true);
    final task=_tasks.removeAt(i);
    try{final f=File(task.path);if(await f.exists())await f.delete();}catch(_){}
    notifyListeners();await _persist();
  }

  Future<void> _run(DownloadTask initial) async {
    var task=initial;
    final file=File(task.path);
    HttpClient? client;
    try {
      await file.parent.create(recursive:true);
      var offset=await file.exists()?await file.length():0;
      client=HttpClient();_clients[task.id]=client;
      task=task.copy(status:'downloading',received:offset);_replace(task);await _persist();
      final request=await client.getUrl(Uri.parse(task.url));
      if(offset>0)request.headers.set(HttpHeaders.rangeHeader,'bytes=$offset-');
      final response=await request.close();
      if(response.statusCode!=HttpStatus.ok&&response.statusCode!=HttpStatus.partialContent){
        throw HttpException('Download server returned HTTP ${response.statusCode}.');
      }
      if(offset>0&&response.statusCode==HttpStatus.ok){offset=0;await file.writeAsBytes([],flush:true);}
      final total=response.contentLength<0?0:offset+response.contentLength;
      task=task.copy(received:offset,total:total);_replace(task);
      final handle=await file.open(mode:FileMode.append);
      try{
        await for(final chunk in response){
          final current=_tasks.where((e)=>e.id==task.id);
          if(current.isEmpty||current.first.status!='downloading')break;
          await handle.writeFrom(chunk);
          final size=await file.length();
          task=task.copy(received:size,total:total);_replace(task);
          if(size==0||size% (1024*1024)<chunk.length)await _persist();
        }
      } finally {await handle.close();}
      final latest=_tasks.where((e)=>e.id==task.id);
      if(latest.isNotEmpty&&latest.first.status=='downloading'){
        task=task.copy(status:'completed',received:await file.length(),total:total);_replace(task);await _persist();
      }
    } catch(e) {
      final i=_tasks.indexWhere((e)=>e.id==task.id);
      if(i>=0&&_tasks[i].status=='downloading'){
        _replace(_tasks[i].copy(status:'error'));await _persist();
      }
    } finally {client?.close(force:true);_clients.remove(task.id);}
  }
}
