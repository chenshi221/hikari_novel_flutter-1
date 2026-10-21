import 'package:hive_ce_flutter/hive_flutter.dart';

import 'sync.dart';

/// 阅读统计：按天和按书累计阅读秒数，以及读过的章节数（同一章同一天只算一次）。
class ReadingStats {
  ReadingStats._();

  static Box get _box => Hive.box('session');

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Map<String, int> _map(String key) => ((_box.get(key) as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as int));

  /// 本机的统计加上同步来的其他设备的统计。[key] 是 day / book。
  static Map<String, int> _total(String key) {
    final out = _map('stats:$key');
    for (final s in Sync.otherStats()) {
      for (final e in ((s[key] as Map?) ?? const {}).entries) {
        out['${e.key}'] = (out['${e.key}'] ?? 0) + (e.value as int);
      }
    }
    return out;
  }

  /// 日期 → 秒
  static Map<String, int> perDay() => _total('day');

  /// aid → 秒
  static Map<String, int> perBook() => _total('book');

  static int get chapters => ((_box.get('stats:chapters') as int?) ?? 0) + Sync.otherStats().fold(0, (a, s) => a + ((s['chapters'] as int?) ?? 0));

  /// 读过这本书的日期（`yyyy-MM-dd`，去重）
  static List<String> bookDays(String aid) => {
    ...((_box.get('stats:days:$aid') as List?) ?? const []).cast<String>(),
    for (final s in Sync.otherStats()) ...(((s['days'] as Map?)?[aid] as List?) ?? const []).cast<String>(),
  }.toList()..sort();

  /// 书的信息（标题、作者、封面），统计页和阅读报告用。
  static ({String title, String author, String img})? meta(String aid) {
    final m = (_box.get('stats:meta') as Map?)?[aid] ?? Sync.otherStats().map((s) => (s['meta'] as Map?)?[aid]).whereType<Map>().firstOrNull;
    return m is Map ? (title: m['t'] as String, author: (m['a'] as String?) ?? '', img: (m['i'] as String?) ?? '') : null;
  }

  static Future<void> setMeta(String aid, String title, String author, String img) async {
    final all = Map.of((_box.get('stats:meta') as Map?) ?? const {});
    all[aid] = {'t': title, 'a': author, 'i': img};
    await _box.put('stats:meta', all);
  }

  static Future<void> addSeconds(String aid, int seconds) async {
    if (seconds <= 0) return;
    final today = dayKey(DateTime.now());
    final days = ((_box.get('stats:days:$aid') as List?) ?? const []).cast<String>();
    if (!days.contains(today)) await _box.put('stats:days:$aid', [...days, today]);
    final day = _map('stats:day'); // 只累加本机自己的，别的设备的统计单独存放
    final book = _map('stats:book');
    final k = dayKey(DateTime.now());
    day[k] = (day[k] ?? 0) + seconds;
    book[aid] = (book[aid] ?? 0) + seconds;
    await _box.put('stats:day', day);
    await _box.put('stats:book', book);
  }

  static Future<void> addChapter(String aid, String cid) async {
    final seen = ((_box.get('stats:seen') as List?) ?? const []).cast<String>();
    final key = '${dayKey(DateTime.now())}:$aid:$cid';
    if (seen.contains(key)) return;
    await _box.put('stats:seen', [...seen.where((e) => e.startsWith(dayKey(DateTime.now()))), key]);
    await _box.put('stats:chapters', ((_box.get('stats:chapters') as int?) ?? 0) + 1);
  }
}
