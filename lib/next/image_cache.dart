import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'session.dart';
import 'volumes.dart';

/// 图片缓存：内存里最多留 [_memBytes] 字节（LRU），磁盘上长期保留，断网后封面和插图还能显示。
/// 网页预览不用它（直接走转发程序）。
class ImageStore {
  ImageStore(this._ref);

  final Ref _ref;
  // 按字节算：封面几十 KB、插图几百 KB，按张数算不是存不下封面就是插图占太多内存
  static const _memBytes = 64 << 20;
  final _mem = <String, Uint8List>{}; // Dart 的 Map 字面量保持插入顺序，当 LRU 用
  var _memUsed = 0;
  final _downloaded = <String>{};
  final _inflight = <String, Future<Uint8List>>{};

  // 网络下载排队：同时最多 [_maxNet] 张，按请求顺序（列表从上到下）。不排队时几十张一起抢带宽，挂代理时谁都快不了，最后一起冒出来。
  // 滑出屏幕的会被 [cancel] 从队里拿掉，所以排着的基本都是眼前这一屏的。
  static const _maxNet = 4;
  int _running = 0;
  final _waiting = <String, Completer<void>>{}; // Map 保持插入顺序
  Directory? _dir;

  Future<Directory> _cacheDir() async => _dir ??= await Directory(p.join((await getApplicationSupportDirectory()).path, 'imgcache')).create(recursive: true);

  /// 两个不同种子的 32 位 FNV-1a 拼成文件名（网页版不支持 64 位字面量）；只为避开 URL 里的特殊字符和过长的名字。
  static String _name(String url) {
    final bytes = utf8.encode(url);
    String hash(int seed) {
      var h = seed;
      for (final b in bytes) {
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
      }
      return h.toRadixString(16).padLeft(8, '0');
    }

    return hash(0x811c9dc5) + hash(0x9747b28c);
  }

  static String _norm(String url) => splitCrop(url).url.replaceFirst('http://', 'https://');

  /// 内存里有就直接给（同步），没有返回 null。
  Uint8List? peek(String rawUrl) {
    final url = _norm(rawUrl);
    final hit = _mem.remove(url);
    return hit == null ? null : _mem[url] = hit;
  }

  /// 这张图是不是本次运行时从网上下载的（界面据此决定要不要淡入）。
  bool downloaded(String rawUrl) => _downloaded.contains(_norm(rawUrl));

  Future<Uint8List> load(String rawUrl) {
    final url = _norm(rawUrl);
    final hit = peek(url);
    if (hit != null) return Future.value(hit);
    final running = _inflight[url];
    if (running != null) return running;
    late final Future<Uint8List> f;
    // 只删自己：被取消后又重新请求时，这里已经换成新的那次了
    f = _fetch(url).whenComplete(() { if (identical(_inflight[url], f)) _inflight.remove(url); });
    return _inflight[url] = f;
  }

  Future<void> _slot(String url) {
    if (_running < _maxNet) {
      _running++;
      return Future.value();
    }
    return (_waiting[url] = Completer<void>()).future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _running--;
    } else {
      _waiting.remove(_waiting.keys.first)!.complete(); // 名额直接交给排在最前面的
    }
  }

  /// 不再需要这张图（滑出屏幕、页面关了）：还在排队的就不下了。已经在下的照常下完存起来。
  void cancel(String rawUrl) {
    final url = _norm(rawUrl);
    final c = _waiting.remove(url);
    if (c == null) return;
    _inflight.remove(url); // 马上又滑回来时重新排队，别拿到这个被取消的结果
    c.completeError(const ImageCancelled());
  }

  Future<Uint8List> _fetch(String url) async {
    final file = File(p.join((await _cacheDir()).path, _name(url)));
    Uint8List bytes;
    if (await file.exists()) {
      bytes = await file.readAsBytes();
    } else {
      await _slot(url);
      try {
        // 封面图床的 https 在国内不开代理时常连不上，http 正常；缓存文件名仍按 https 地址算，旧缓存照用
        final res = await _ref.read(imageDioProvider).get<List<int>>(url.replaceFirst('https://img.wenku8.com/', 'http://img.wenku8.com/'));
        bytes = Uint8List.fromList(res.data!);
      } finally {
        _release();
      }
      await file.writeAsBytes(bytes);
      _downloaded.add(url);
    }
    _memUsed += bytes.length - (_mem.remove(url)?.length ?? 0);
    _mem[url] = bytes;
    while (_memUsed > _memBytes && _mem.length > 1) {
      _memUsed -= _mem.remove(_mem.keys.first)!.length;
    }
    return bytes;
  }

  Future<void> clearDisk() async {
    final dir = await _cacheDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
    _mem.clear();
    _memUsed = 0;
  }

  /// 磁盘缓存超过 [maxBytes] 时按修改时间从旧到新删，删到上限的 80%；本地书架里的书的封面、卷封面不删。
  /// shortcut: 离线缓存的插图也可能被清掉，联网时会重新下载；以后要区分就给离线插图单独目录
  Future<void> trim({int maxBytes = 500 << 20}) async => trimDir(await _cacheDir(), maxBytes, keep: {for (final url in [...LibraryStore.covers(), ...Volumes.allCovers()]) _name(_norm(url))});

  Future<int> diskBytes() async {
    final dir = await _cacheDir();
    var n = 0;
    await for (final f in dir.list()) {
      if (f is File) n += await f.length();
    }
    return n;
  }
}

/// 目录总大小超过 [maxBytes] 时，按修改时间从旧到新删文件，直到不超过 [maxBytes] 的 80%。
/// 文件名在 [keep] 里的不删（但计入总大小）。
Future<void> trimDir(Directory dir, int maxBytes, {Set<String> keep = const {}}) async {
  final files = <(File, FileStat)>[];
  var total = 0;
  await for (final f in dir.list()) {
    if (f is! File) continue;
    final st = await f.stat();
    total += st.size;
    if (!keep.contains(p.basename(f.path))) files.add((f, st));
  }
  if (total <= maxBytes) return;
  files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
  for (final (f, st) in files) {
    if (total <= maxBytes * 0.8) break;
    await f.delete();
    total -= st.size;
  }
}

/// 自选封面的裁剪框记在地址后面：`图片地址#crop=左,上,宽,高`（都是 0~1 的比例）。下载、缓存都按去掉它的地址算。
({String url, Rect? crop}) splitCrop(String s) {
  final i = s.indexOf('#crop=');
  if (i < 0) return (url: s, crop: null);
  final n = s.substring(i + 6).split(',').map(double.tryParse).toList();
  if (n.length != 4 || n.contains(null)) return (url: s.substring(0, i), crop: null);
  return (url: s.substring(0, i), crop: Rect.fromLTWH(n[0]!, n[1]!, n[2]!, n[3]!));
}

String withCrop(String url, Rect r) => '$url#crop=${[r.left, r.top, r.width, r.height].map((e) => e.toStringAsFixed(4)).join(',')}';

class ImageCancelled implements Exception {
  const ImageCancelled();
}

final imageStoreProvider = Provider<ImageStore>((ref) => ImageStore(ref));
