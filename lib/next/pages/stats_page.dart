import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../data/wenku8/wenku8_parser.dart';
import '../read_state.dart';
import '../router.dart';
import '../stats.dart';
import '../volumes.dart';
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
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: const Text('书籍墙'),
                    subtitle: Text('读完了 ${Volumes.allDone().length} 卷'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.wall),
                  ),
                ),
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
                for (final e in top.take(20))
                  Builder(
                    builder: (context) {
                      final info = ReadingStats.info(e.key);
                      final img = info.img.isNotEmpty ? info.img : Wenku8Parser.coverUrl(e.key);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(width: 40, height: 54, child: CoverImage(img)),
                        title: Text(info.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${ReadingStats.bookDays(e.key).length} 天 · ${ReadState.read(e.key).length} 章已读'),
                        trailing: Text(_duration(e.value)),
                        onTap: () => context.push(Routes.report(e.key)),
                        onLongPress: () => context.push(Routes.novel(e.key)),
                      );
                    },
                  ),
                const SizedBox(height: 4),
                Text('点一本书看阅读报告，长按进详情', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
    );
  }
}
