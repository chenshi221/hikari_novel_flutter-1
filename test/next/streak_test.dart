import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/next/pages/stats_page.dart';

void main() {
  test('连续阅读天数：今天没读从昨天数，断一天就停', () {
    final now = DateTime(2026, 3, 10, 20);
    expect(readingStreak({'2026-03-10': 60, '2026-03-09': 60, '2026-03-08': 0, '2026-03-07': 60}, now), 2);
    expect(readingStreak({'2026-03-09': 60, '2026-03-08': 60}, now), 2);
    expect(readingStreak({'2026-03-08': 60}, now), 0);
    // 跨月
    expect(readingStreak({'2026-03-01': 60, '2026-02-28': 60}, DateTime(2026, 3, 1)), 2);
  });
}
