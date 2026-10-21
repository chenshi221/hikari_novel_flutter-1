import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/cat_chapter.dart';
import '../models/content.dart';
import 'data.dart';
import 'image_cache.dart';

/// 离线章节缓存。正文放在 LazyBox（只在读的时候才从磁盘取，不常驻内存），
/// 章数、大小、书的信息放在一个很小的普通 Box 里，列表和计数不用碰正文。
///
/// - `chapters`（LazyBox）：`aid:cid` → `{t: 正文, i: [插图地址]}`
/// - `chapter_index`（Box）：`aid:cid` → 正文字数；`meta:aid` → 书名、总章数、封面、第一章
class ChapterCache {
  ChapterCache._();

  static late LazyBox _text;
  static late Box _index;

  static Future<void> open() async {
    _text = await Hive.openLazyBox('chapters');
    _index = await Hive.openBox('chapter_index');
    PageStore._box = await Hive.openLazyBox('pages');
    await _migrate();
  }

  /// 旧版本把 meta 和正文放在同一个 Box 里、没有索引：一次性搬过来。
  static Future<void> _migrate() async {
    if (_index.get('migrated') == true) return;
    for (final key in _text.keys.whereType<String>().toList()) {
      final v = await _text.get(key);
      if (v is! Map) continue;
      if (key.startsWith('meta:')) {
        await _index.put(key, v);
        await _text.delete(key);
      } else if (!_index.containsKey(key)) {
        await _index.put(key, (v['t'] as String).length);
      }
    }
    await _index.put('migrated', true);
  }

  static Future<Content?> get(String aid, String cid) async {
    final v = await _text.get('$aid:$cid');
    return v is Map ? Content(text: v['t'] as String, images: (v['i'] as List).cast<String>()) : null;
  }

  static Future<void> put(String aid, String cid, Content c) async {
    await _text.put('$aid:$cid', {'t': c.text, 'i': c.images});
    await _index.put('$aid:$cid', c.text.length);
  }

  static bool has(String aid, String cid) => _index.containsKey('$aid:$cid');

  static Iterable<String> _keys(String aid) => _index.keys.whereType<String>().where((k) => k.startsWith('$aid:'));

  static int count(String aid) => _keys(aid).length;

  static Future<void> setMeta(String aid, String title, int total, String img, String firstCid) => _index.put('meta:$aid', {'title': title, 'total': total, 'img': img, 'first': firstCid});

  /// 有缓存的书：aid → (书名, 总章数, 封面地址, 第一章 cid)
  static Map<String, (String, int, String, String)> books() => {
    for (final k in _index.keys.whereType<String>().where((k) => k.startsWith('meta:')))
      k.substring(5): (
        (_index.get(k) as Map)['title'] as String,
        (_index.get(k) as Map)['total'] as int,
        ((_index.get(k) as Map)['img'] as String?) ?? '',
        ((_index.get(k) as Map)['first'] as String?) ?? '',
      ),
  };

  static Future<void> remove(String aid) async {
    final keys = [..._keys(aid), 'meta:$aid'];
    await _text.deleteAll(keys);
    await _index.deleteAll(keys);
  }

  static Future<void> removeChapters(String aid, Iterable<String> cids) async {
    final keys = [for (final c in cids) '$aid:$c'];
    await _text.deleteAll(keys);
    await _index.deleteAll(keys);
  }

  /// 估算占用：按每个字符 3 字节（UTF-8 中文）算，不含插图。
  static String sizeLabel(String aid) {
    final chars = _keys(aid).fold<int>(0, (a, k) => a + ((_index.get(k) as int?) ?? 0));
    final bytes = chars * 3;
    return bytes > 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB' : '${(bytes / 1024).round()} KB';
  }
}

/// 网页原文的离线备份（详情、目录、书架、用户页）：联网并解析成功后才更新，断网时拿来顶替。
/// 最多保留 [_cap] 页，超出删最旧的；账号私有的页面（书架）键里带用户 ID，退出登录时清掉。
class PageStore {
  PageStore._();

  static late LazyBox _box;
  static const _cap = 400;

  static Future<String?> get(String key) async => await _box.get(key) as String?;

  static Future<void> put(String key, String html) async {
    await _box.put(key, html);
    while (_box.length > _cap) {
      await _box.deleteAt(0);
    }
  }

  static Future<void> removeScope(String scope) => _box.deleteAll(_box.keys.where((k) => k is String && k.startsWith('$scope|')).toList());
}

class DownloadState {
  const DownloadState({this.done = 0, this.total = 0, this.running = false, this.error});

  final int done;
  final int total;
  final bool running;
  final String? error;
}

/// 缓存下载：一本书一个任务，章节一章一章下载（放慢一点，避免被网站限流），可暂停。
/// 正文和插图都下载，断网后插图也能显示。
class DownloadController extends Notifier<Map<String, DownloadState>> {
  final _cancelled = <String>{};

  @override
  Map<String, DownloadState> build() => {};

  void cancel(String aid) => _cancelled.add(aid);

  /// 删除缓存后把这本书的下载状态一起清掉（不重建整个 Notifier，免得打断别的书的下载）。
  void forget(String aid) {
    _cancelled.add(aid);
    state = {...state}..remove(aid);
  }

  /// 下载 [chapters] 里还没缓存的章节；[total] 是全书章数，用来显示整本书的进度。
  Future<void> start(String aid, String title, List<CatChapter> chapters, {int? total, String img = '', String firstCid = ''}) async {
    if (state[aid]?.running ?? false) return;
    final api = ref.read(apiProvider);
    final images = ref.read(imageStoreProvider);
    final all = total ?? chapters.length;
    _cancelled.remove(aid);
    void emit({bool running = true, String? error}) {
      if (!ref.mounted) return;
      state = {...state, aid: DownloadState(done: ChapterCache.count(aid), total: all, running: running, error: error)};
    }

    emit();
    await ChapterCache.setMeta(aid, title, all, img, firstCid.isEmpty && chapters.isNotEmpty ? chapters.first.cid : firstCid);
    try {
      for (final c in chapters) {
        if (_cancelled.contains(aid)) break;
        if (ChapterCache.has(aid, c.cid)) continue;
        final content = await api.chapter(aid, c.cid);
        // 请求期间可能已经暂停或删除了缓存：此时不能再写回去
        if (_cancelled.contains(aid)) break;
        await ChapterCache.put(aid, c.cid, content);
        for (final url in content.images) {
          try {
            await images.load(url);
          } catch (_) {}
        }
        emit();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      emit(running: false);
    } catch (e) {
      emit(running: false, error: e.toString());
    }
  }
}

final downloadProvider = NotifierProvider<DownloadController, Map<String, DownloadState>>(DownloadController.new);
