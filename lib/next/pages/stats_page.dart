import 'package:flutter/material.dart';

import '../cache.dart';
import '../history.dart';
import '../stats.dart';
import '../widgets.dart';

String _duration(int seconds) => seconds >= 3600 ? '${seconds ~/ 3600} 小时 ${(seconds % 3600) ~/ 60} 分' : '${(seconds / 60).ceil()} 分钟';

/// 阅读统计：总时长、近 7 天柱状图、读得最久的书。
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perDay = ReadingStats.perDay();
    final perBook = ReadingStats.perBook();
    final total = perDay.values.fold(0, (a, b) => a + b);
    final today = perDay[ReadingStats.dayKey(DateTime.now())] ?? 0;
    final days = [for (var i = 6; i >= 0; i--) DateTime.now().subtract(Duration(days: i))];
    final maxSec = days.map((d) => perDay[ReadingStats.dayKey(d)] ?? 0).fold(1, (a, b) => a > b ? a : b);
    final titles = {for (final e in ReadingHistory.all()) e.aid: e.title, for (final e in ChapterCache.books().entries) e.key: e.value.$1};
    final top = perBook.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    Widget tile(String label, String value) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: theme.textTheme.titleLarge), const SizedBox(height: 4), Text(label, style: theme.textTheme.bodySmall)]),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('阅读统计')),
      body: total == 0 && ReadingStats.chapters == 0
          ? const StatePanel(title: '还没有阅读数据', detail: '读几章之后这里会出现统计。')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(children: [tile('累计阅读', _duration(total)), const SizedBox(width: 12), tile('今天', _duration(today))]),
                const SizedBox(height: 12),
                Row(children: [tile('读过的章节', '${ReadingStats.chapters}'), const SizedBox(width: 12), tile('读过的书', '${perBook.length}')]),
                const SizedBox(height: 24),
                Text('近 7 天', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in days)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('${((perDay[ReadingStats.dayKey(d)] ?? 0) / 60).round()}', style: theme.textTheme.labelSmall),
                                const SizedBox(height: 4),
                                Container(height: 100 * (perDay[ReadingStats.dayKey(d)] ?? 0) / maxSec + 2, decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(4))),
                                const SizedBox(height: 4),
                                Text('${d.month}/${d.day}', style: theme.textTheme.labelSmall),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text('单位：分钟', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                Text('读得最久', style: theme.textTheme.titleMedium),
                for (final e in top.take(10)) ListTile(contentPadding: EdgeInsets.zero, title: Text(titles[e.key] ?? '书号 ${e.key}', maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Text(_duration(e.value))),
              ],
            ),
    );
  }
}
