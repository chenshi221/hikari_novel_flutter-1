import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/cat_chapter.dart';
import '../models/content.dart';
import 'data.dart';

/// 离线章节缓存：`aid:cid` → 正文，`meta:aid` → 书名和总章数。读章节时先查这里。
class ChapterCache {
  ChapterCache._();

  static late Box _box;

  static Future<void> open() async {
    _box = await Hive.openBox('chapters');
    PageStore._box = await Hive.openBox('pages');
  }

  static Content? get(String aid, String cid) {
    final v = _box.get('$aid:$cid');
    return v is Map ? Content(text: v['t'] as String, images: (v['i'] as List).cast<String>()) : null;
  }

  static Future<void> put(String aid, String cid, Content c) => _box.put('$aid:$cid', {'t': c.text, 'i': c.images});

  static bool has(String aid, String cid) => _box.containsKey('$aid:$cid');

  static int count(String aid) => _box.keys.where((k) => k is String && k.startsWith('$aid:')).length;

  static Future<void> setMeta(String aid, String title, int total, String img, String firstCid) => _box.put('meta:$aid', {'title': title, 'total': total, 'img': img, 'first': firstCid});

  /// 有缓存的书：aid → (书名, 总章数, 封面地址, 第一章 cid)
  static Map<String, (String, int, String, String)> books() => {
    for (final k in _box.keys.whereType<String>().where((k) => k.startsWith('meta:')))
      k.substring(5): (
        (_box.get(k) as Map)['title'] as String,
        (_box.get(k) as Map)['total'] as int,
        ((_box.get(k) as Map)['img'] as String?) ?? '',
        ((_box.get(k) as Map)['first'] as String?) ?? '',
      ),
  };

  static Future<void> remove(String aid) => _box.deleteAll(_box.keys.where((k) => k is String && (k.startsWith('$aid:') || k == 'meta:$aid')));

  static Future<void> removeChapters(String aid, Iterable<String> cids) => _box.deleteAll([for (final c in cids) '$aid:$c']);

  /// 估算占用：按每个字符 3 字节（UTF-8 中文）算。
  static String sizeLabel(String aid) {
    var chars = 0;
    for (final k in _box.keys.where((k) => k is String && k.startsWith('$aid:'))) {
      final v = _box.get(k);
      if (v is Map) chars += (v['t'] as String).length;
    }
    final bytes = chars * 3;
    return bytes > 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB' : '${(bytes / 1024).round()} KB';
  }
}

/// 网页原文的离线备份（详情、目录、书架、用户页）：联网成功时更新，断网时拿来顶替。
class PageStore {
  PageStore._();

  static late Box _box;

  static String? get(String url) => _box.get(url) as String?;

  static Future<void> put(String url, String html) => _box.put(url, html);
}

class DownloadState {
  const DownloadState({this.done = 0, this.total = 0, this.running = false, this.error});

  final int done;
  final int total;
  final bool running;
  final String? error;
}

/// 缓存下载：一本书一个任务，章节一章一章下载（放慢一点，避免被网站限流），可取消。
class DownloadController extends Notifier<Map<String, DownloadState>> {
  final _cancelled = <String>{};

  @override
  Map<String, DownloadState> build() => {};

  void cancel(String aid) => _cancelled.add(aid);

  /// 下载 [chapters] 里还没缓存的章节；[total] 是全书章数，用来显示整本书的进度。
  Future<void> start(String aid, String title, List<CatChapter> chapters, {int? total, String img = '', String firstCid = ''}) async {
    if (state[aid]?.running ?? false) return;
    final api = ref.read(apiProvider);
    final all = total ?? chapters.length;
    _cancelled.remove(aid);
    void emit({bool running = true, String? error}) => state = {...state, aid: DownloadState(done: ChapterCache.count(aid), total: all, running: running, error: error)};
    emit();
    await ChapterCache.setMeta(aid, title, all, img, firstCid.isEmpty && chapters.isNotEmpty ? chapters.first.cid : firstCid);
    try {
      for (final c in chapters) {
        if (_cancelled.contains(aid)) break;
        if (ChapterCache.has(aid, c.cid)) continue;
        await ChapterCache.put(aid, c.cid, await api.chapter(aid, c.cid));
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
