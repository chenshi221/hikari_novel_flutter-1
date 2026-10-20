import 'package:hive_ce_flutter/hive_flutter.dart';

class HistoryEntry {
  const HistoryEntry({required this.aid, required this.title, required this.img, required this.cid, required this.chapter, required this.time});

  final String aid;
  final String title;
  final String img;
  final String cid;
  final String chapter;
  final DateTime time;
}

/// 阅读历史：每本书一条，记最后读到的章节和时间，新的在前，最多 300 本。
class ReadingHistory {
  ReadingHistory._();

  static Box get _box => Hive.box('session');

  static List<HistoryEntry> all() => ((_box.get('history2') as List?) ?? const []).cast<Map>().map((e) {
    return HistoryEntry(
      aid: e['aid'] as String,
      title: e['title'] as String,
      img: e['img'] as String,
      cid: e['cid'] as String,
      chapter: e['chapter'] as String,
      time: DateTime.fromMillisecondsSinceEpoch(e['time'] as int),
    );
  }).toList();

  static Future<void> record(String aid, String title, String img, String cid, String chapter) {
    final rest = ((_box.get('history2') as List?) ?? const []).cast<Map>().where((e) => e['aid'] != aid);
    return _box.put('history2', [
      {'aid': aid, 'title': title, 'img': img, 'cid': cid, 'chapter': chapter, 'time': DateTime.now().millisecondsSinceEpoch},
      ...rest,
    ].take(300).toList());
  }

  static Future<void> remove(String aid) => _box.put('history2', ((_box.get('history2') as List?) ?? const []).cast<Map>().where((e) => e['aid'] != aid).toList());

  static Future<void> clear() => _box.delete('history2');
}
