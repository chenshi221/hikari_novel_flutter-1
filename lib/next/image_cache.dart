import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'session.dart';

/// 图片缓存：内存里最多留 [_memCap] 张（LRU），磁盘上长期保留，断网后封面和插图还能显示。
/// 网页预览不用它（直接走转发程序）。
class ImageStore {
  ImageStore(this._ref);

  final Ref _ref;
  static const _memCap = 80;
  final _mem = <String, Uint8List>{}; // Dart 的 Map 字面量保持插入顺序，当 LRU 用
  final _inflight = <String, Future<Uint8List>>{};
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

  Future<Uint8List> load(String rawUrl) {
    final url = rawUrl.replaceFirst('http://', 'https://');
    final hit = _mem.remove(url);
    if (hit != null) return Future.value(_mem[url] = hit);
    return _inflight[url] ??= _fetch(url).whenComplete(() => _inflight.remove(url));
  }

  Future<Uint8List> _fetch(String url) async {
    final file = File(p.join((await _cacheDir()).path, _name(url)));
    Uint8List bytes;
    if (await file.exists()) {
      bytes = await file.readAsBytes();
    } else {
      final res = await _ref.read(imageDioProvider).get<List<int>>(url);
      bytes = Uint8List.fromList(res.data!);
      await file.writeAsBytes(bytes);
    }
    _mem[url] = bytes;
    while (_mem.length > _memCap) {
      _mem.remove(_mem.keys.first);
    }
    return bytes;
  }

  Future<void> clearDisk() async {
    final dir = await _cacheDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
    _mem.clear();
  }

  Future<int> diskBytes() async {
    final dir = await _cacheDir();
    var n = 0;
    await for (final f in dir.list()) {
      if (f is File) n += await f.length();
    }
    return n;
  }
}

final imageStoreProvider = Provider<ImageStore>((ref) => ImageStore(ref));
