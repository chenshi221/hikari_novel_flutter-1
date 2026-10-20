import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/cat_chapter.dart';
import '../models/content.dart';
import 'data.dart';

/// 离线章节缓存：`aid:cid` → 正文，`meta:aid` → 书名和总章数。读章节时先查这里。
class ChapterCache {
  ChapterCache._();

  static late Box _box;

  static Future<void> open() async => _box = await Hive.openBox('chapters');

  static Content? get(String aid, String cid) {
    final v = _box.get('$aid:$cid');
    return v is Map ? Content(text: v['t'] as String, images: (v['i'] as List).cast<String>()) : null;
  }

  static Future<void> put(String aid, String cid, Content c) => _box.put('$aid:$cid', {'t': c.text, 'i': c.images});

  static bool has(String aid, String cid) => _box.containsKey('$aid:$cid');

  static int count(String aid) => _box.keys.where((k) => k is String && k.startsWith('$aid:')).length;

  static Future<void> setMeta(String aid, String title, int total) => _box.put('meta:$aid', {'title': title, 'total': total});

  /// 有缓存的书：aid → (书名, 总章数)
  static Map<String, (String, int)> books() => {
    for (final k in _box.keys.whereType<String>().where((k) => k.startsWith('meta:')))
      k.substring(5): ((_box.get(k) as Map)['title'] as String, (_box.get(k) as Map)['total'] as int),
  };

  static Future<void> remove(String aid) => _box.deleteAll(_box.keys.where((k) => k is String && (k.startsWith('$aid:') || k == 'meta:$aid')));
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

  Future<void> start(String aid, String title, List<CatChapter> chapters) async {
    if (state[aid]?.running ?? false) return;
    final api = ref.read(apiProvider);
    _cancelled.remove(aid);
    var done = chapters.where((c) => ChapterCache.has(aid, c.cid)).length;
    void emit({bool running = true, String? error}) => state = {...state, aid: DownloadState(done: done, total: chapters.length, running: running, error: error)};
    emit();
    await ChapterCache.setMeta(aid, title, chapters.length);
    try {
      for (final c in chapters) {
        if (_cancelled.contains(aid)) break;
        if (ChapterCache.has(aid, c.cid)) continue;
        await ChapterCache.put(aid, c.cid, await api.chapter(aid, c.cid));
        done++;
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
