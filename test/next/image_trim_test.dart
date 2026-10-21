import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/next/image_cache.dart';

void main() {
  test('trimDir 超限时删最旧的，未超限不动', () async {
    final dir = await Directory.systemTemp.createTemp('trim');
    addTearDown(() => dir.delete(recursive: true));
    final now = DateTime.now();
    for (var i = 0; i < 5; i++) {
      final f = File('${dir.path}/f$i')..writeAsBytesSync(List.filled(100, 0));
      f.setLastModifiedSync(now.subtract(Duration(minutes: 5 - i))); // f0 最旧
    }
    await trimDir(dir, 500);
    expect(dir.listSync().length, 5);

    await trimDir(dir, 400); // 总 500 > 400：删到 ≤320，即只留最新的 3 个
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(names, {'f2', 'f3', 'f4'});
  });
}
