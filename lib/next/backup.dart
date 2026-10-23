import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import 'sync.dart';

/// 完整备份：在同步用的快照（进度、历史、书签、已读章节、统计、规则备注）之外，
/// 再带上书架（书和分类）、各种设置和每卷的自选封面 / 评分。登录信息、WebDAV 密码、缓存的正文都不在里面。
class Backup {
  Backup._();

  static Box get _box => Hive.box('session');

  /// 这些键（或前缀）会进备份
  static const _exact = {'lib:books', 'lib:cats', 'shelfTabOrder', 'shelfOpts', 'catReverse', 'incognito'};
  static const _prefixes = ['shelfOrder:', 'vcover2:', 'vrate:', 'r.', 'p.', 'swipe', 'chl:'];

  static bool _wanted(String k) => _exact.contains(k) || _prefixes.any(k.startsWith);

  static String make() {
    final extra = {for (final k in _box.keys.whereType<String>().where(_wanted)) k: _box.get(k)};
    return jsonEncode({...Sync.snapshot(), 'backup': 2, 'extra': extra});
  }

  /// 恢复：同步快照按同步规则并入（本机自己导出的跳过）；书架里没有的书、没有的分类补上；
  /// 其余设置只补本机还没有的，不覆盖现在的设置。返回恢复了多少本书。
  static Future<int> restore(String json) async {
    final m = jsonDecode(json) as Map<String, dynamic>;
    if (m['device'] != Sync.deviceId) await Sync.importBackup(json);
    final extra = (m['extra'] as Map?) ?? const {};
    var books = 0;
    for (final e in extra.entries) {
      final k = e.key as String;
      if (!_wanted(k)) continue;
      if (k == 'lib:books') {
        final mine = Map.of((_box.get(k) as Map?) ?? const {});
        for (final b in (e.value as Map).entries) {
          if (!mine.containsKey(b.key)) {
            mine[b.key] = b.value;
            books++;
          }
        }
        await _box.put(k, mine);
      } else if (k == 'lib:cats') {
        final mine = ((_box.get(k) as List?) ?? const []).cast<Map>().toList();
        final ids = mine.map((c) => c['id']).toSet();
        await _box.put(k, [...mine, for (final c in (e.value as List).cast<Map>()) if (!ids.contains(c['id'])) c]);
      } else if (!_box.containsKey(k)) {
        await _box.put(k, e.value);
      }
    }
    return books;
  }
}
