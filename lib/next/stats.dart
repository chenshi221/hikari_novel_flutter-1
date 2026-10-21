import 'package:hive_ce_flutter/hive_flutter.dart';

/// 阅读统计：按天和按书累计阅读秒数，以及读过的章节数（同一章同一天只算一次）。
class ReadingStats {
  ReadingStats._();

  static Box get _box => Hive.box('session');

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Map<String, int> _map(String key) => ((_box.get(key) as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as int));

  /// 日期 → 秒
  static Map<String, int> perDay() => _map('stats:day');

  /// aid → 秒
  static Map<String, int> perBook() => _map('stats:book');

  static int get chapters => (_box.get('stats:chapters') as int?) ?? 0;

  /// 读过这本书的日期（`yyyy-MM-dd`，去重）
  static List<String> bookDays(String aid) => (((_box.get('stats:days:$aid') as List?) ?? const []).cast<String>().toList())..sort();

  /// 书的信息（标题、作者、封面），统计页和阅读报告用。
  static ({String title, String author, String img})? meta(String aid) {
    final m = (_box.get('stats:meta') as Map?)?[aid];
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
    final days = bookDays(aid);
    if (!days.contains(today)) await _box.put('stats:days:$aid', [...days, today]);
    final day = perDay();
    final book = perBook();
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
    await _box.put('stats:chapters', chapters + 1);
  }
}
