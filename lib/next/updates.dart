import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'data.dart';

class UpdateEntry {
  const UpdateEntry({required this.aid, required this.title, required this.img, required this.chapter, required this.cid, required this.time});

  final String aid;
  final String title;
  final String img;
  final String chapter;
  final String cid;
  final DateTime time;
}

/// 书架更新追踪：对比每本书上次看到的目录，新增的章节记入"更新"列表。
class UpdateStore {
  UpdateStore._();

  static Box get _box => Hive.box('session');

  static List<UpdateEntry> feed() => ((_box.get('updates') as List?) ?? const []).cast<Map>().map((e) {
    return UpdateEntry(aid: e['aid'] as String, title: e['title'] as String, img: e['img'] as String, chapter: e['chapter'] as String, cid: e['cid'] as String, time: DateTime.fromMillisecondsSinceEpoch(e['time'] as int));
  }).toList();

  static int get lastCheck => (_box.get('updates:check') as int?) ?? 0;

  /// 上次打开"更新"页的时间，比它新的条目显示为未读。
  static int get lastSeen => (_box.get('updates:seen') as int?) ?? 0;

  static Future<void> markSeen() => _box.put('updates:seen', DateTime.now().millisecondsSinceEpoch);

  static int unread() => feed().where((e) => e.time.millisecondsSinceEpoch > lastSeen).length;

  /// 这本书最近一次发现更新的时间（毫秒），没有为 0。
  static int updatedAt(String aid) => (_box.get('updates:at:$aid') as int?) ?? 0;

  static Map get _known => (_box.get('updates:known') as Map?) ?? {};

  static Future<void> save(Map<String, int> known, List<Map> feed, {required Map<String, int> at}) async {
    await _box.put('updates:known', known);
    await _box.put('updates', feed.take(300).toList());
    await _box.put('updates:check', DateTime.now().millisecondsSinceEpoch);
    for (final e in at.entries) {
      await _box.put('updates:at:${e.key}', e.value);
    }
  }

  static Map<String, int> knownCounts() => _known.map((k, v) => MapEntry(k as String, v as int));
}

class UpdateProgress {
  const UpdateProgress({this.done = 0, this.total = 0, this.running = false, this.error});

  final int done;
  final int total;
  final bool running;
  final String? error;
}

class UpdateController extends Notifier<UpdateProgress> {
  @override
  UpdateProgress build() => const UpdateProgress();

  /// 检查书架里所有书。第一次只记录当前章节数作为基准，不产生更新。
  Future<void> refresh() async {
    if (state.running) return;
    final api = ref.read(apiProvider);
    state = const UpdateProgress(running: true);
    try {
      final books = <String, ({String title, String img})>{};
      for (var classId = 0; classId < 6; classId++) {
        for (final b in (await api.bookshelf(classId)).list) {
          books[b.aid] = (title: b.title, img: b.img);
        }
      }
      final known = UpdateStore.knownCounts();
      final feed = UpdateStore.feed().map((e) => {'aid': e.aid, 'title': e.title, 'img': e.img, 'chapter': e.chapter, 'cid': e.cid, 'time': e.time.millisecondsSinceEpoch}).toList();
      final at = <String, int>{};
      final fresh = <Map>[];
      var done = 0;
      state = UpdateProgress(running: true, total: books.length);
      for (final e in books.entries) {
        final chapters = (await api.novel(e.key)).catalogue.expand((v) => v.chapters).toList();
        final before = known[e.key];
        if (before != null && chapters.length > before) {
          final now = DateTime.now().millisecondsSinceEpoch;
          for (final c in chapters.skip(before)) {
            fresh.add({'aid': e.key, 'title': e.value.title, 'img': e.value.img, 'chapter': c.title, 'cid': c.cid, 'time': now});
          }
          at[e.key] = now;
        }
        known[e.key] = chapters.length;
        state = UpdateProgress(running: true, done: ++done, total: books.length);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      known.removeWhere((aid, _) => !books.containsKey(aid));
      await UpdateStore.save(known, [...fresh.reversed, ...feed], at: at);
      state = UpdateProgress(done: done, total: books.length);
    } catch (e) {
      state = UpdateProgress(error: e.toString());
    }
  }
}

final updateProvider = NotifierProvider<UpdateController, UpdateProgress>(UpdateController.new);
