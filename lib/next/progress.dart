import 'package:hive_ce_flutter/hive_flutter.dart';

/// 阅读进度：记在哪一章、章内第几个字符。按字符偏移保存，改字号、换设备尺寸后仍能回到同一处。
class ReadingProgress {
  const ReadingProgress(this.cid, this.offset);

  final String cid;
  final int offset;

  static Box get _box => Hive.box('session');

  static ReadingProgress? of(String aid) {
    final v = _box.get('progress:$aid');
    return v is List && v.length == 2 ? ReadingProgress(v[0] as String, v[1] as int) : null;
  }

  static Future<void> save(String aid, String cid, int offset) => _box.put('progress:$aid', [cid, offset]);
}
