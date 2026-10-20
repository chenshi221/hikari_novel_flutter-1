import 'package:hive_ce_flutter/hive_flutter.dart';

/// 浏览历史：最近看过的 200 本，新的在前。
class BrowsingHistory {
  BrowsingHistory._();

  static Box get _box => Hive.box('session');

  static List<({String aid, String title, String img})> all() => ((_box.get('history') as List?) ?? const [])
      .cast<Map>()
      .map((e) => (aid: e['aid'] as String, title: e['title'] as String, img: e['img'] as String))
      .toList();

  static Future<void> add(String aid, String title, String img) {
    final rest = ((_box.get('history') as List?) ?? const []).cast<Map>().where((e) => e['aid'] != aid);
    return _box.put('history', [
      {'aid': aid, 'title': title, 'img': img},
      ...rest,
    ].take(200).toList());
  }

  static Future<void> clear() => _box.delete('history');
}
