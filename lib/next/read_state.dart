import 'package:hive_ce_flutter/hive_flutter.dart';

import 'volumes.dart';

/// 每本书哪些章节读过（读到章末，或者翻到了下一章）、读过多少字，用于详情页的已读/未读和阅读报告。
class ReadState {
  ReadState._();

  static Box get _box => Hive.box('session');

  static Set<String> read(String aid) => ((_box.get('read:$aid') as List?) ?? const []).cast<String>().toSet();

  static bool isRead(String aid, String cid) => read(aid).contains(cid);

  /// 标记已读；第一次标记时把字数计入这本书的"已读字数"。
  static Future<void> mark(String aid, String cid, int chars) async {
    final set = read(aid);
    if (!set.add(cid)) return;
    await _box.put('read:$aid', set.toList());
    await _box.put('readchars:$aid', readChars(aid) + chars);
    await Volumes.refreshDone(aid);
  }

  /// 手动标记一批章节已读 / 未读（详情页多选）。不改"已读字数"。
  /// shortcut: 同步时已读记录按并集合并，标成未读不会同步到其他设备；要同步得给已读加墓碑
  static Future<void> setRead(String aid, Iterable<String> cids, bool read) {
    final set = ReadState.read(aid);
    read ? set.addAll(cids) : set.removeAll(cids);
    return _box.put('read:$aid', set.toList()).then((_) => Volumes.refreshDone(aid));
  }

  static int readChars(String aid) => (_box.get('readchars:$aid') as int?) ?? 0;

  /// 书的评分（1 到 5 星），没评过为 0。
  static int rating(String aid) => (_box.get('rating:$aid') as int?) ?? 0;

  static Future<void> setRating(String aid, int stars) => _box.put('rating:$aid', stars);
}
