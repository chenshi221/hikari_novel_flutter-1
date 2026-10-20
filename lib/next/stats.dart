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

  static Future<void> addSeconds(String aid, int seconds) async {
    if (seconds <= 0) return;
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
