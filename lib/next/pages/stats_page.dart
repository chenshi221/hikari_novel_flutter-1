import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/wenku8/wenku8_parser.dart';
import '../read_state.dart';
import '../router.dart';
import '../stats.dart';
import '../volumes.dart';
import '../widgets.dart';

String _duration(int seconds) => seconds >= 3600 ? '${seconds ~/ 3600} 小时 ${(seconds % 3600) ~/ 60} 分' : '${(seconds / 60).ceil()} 分钟';

/// 连续阅读天数：从今天往前数（今天还没读就从昨天开始数）
int readingStreak(Map<String, int> perDay, DateTime now) {
  var d = DateTime(now.year, now.month, now.day);
  if ((perDay[ReadingStats.dayKey(d)] ?? 0) == 0) d = d.subtract(const Duration(days: 1));
  var n = 0;
  while ((perDay[ReadingStats.dayKey(d)] ?? 0) > 0) {
    n++;
    d = d.subtract(const Duration(days: 1));
  }
  return n;
}

/// 阅读统计：今天 / 连续天数，周 / 月 / 年柱状图（带平均线），最近几个月的阅读日历，总数，读得最久的书。
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  int _range = 0; // 0 周、1 月、2 年
  int? _picked; // 点中的那根柱子

  /// 柱状图的数据：(标签, 秒, 点中时显示的日期)。年按自然月合计。
  List<(String, int, String)> _bars(Map<String, int> perDay, DateTime now) {
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    if (_range == 2) {
      return [
        for (var i = 11; i >= 0; i--)
          () {
            final m = DateTime(now.year, now.month - i);
            final prefix = '${m.year}-${m.month.toString().padLeft(2, '0')}-';
            return ('${m.month}月', perDay.entries.where((e) => e.key.startsWith(prefix)).fold(0, (a, e) => a + e.value), '${m.year} 年 ${m.month} 月');
          }(),
      ];
    }
    final n = _range == 0 ? 7 : 30;
    return [
      for (var i = n - 1; i >= 0; i--)
        () {
          final d = DateTime(now.year, now.month, now.day - i);
          final label = _range == 0 ? week[d.weekday - 1] : (i % 5 == 0 ? '${d.month}/${d.day}' : '');
          return (label, perDay[ReadingStats.dayKey(d)] ?? 0, '${d.month}月${d.day}日 周${week[d.weekday - 1]}');
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    ref.watch(volumeChangesProvider);
    final queue = ref.read(volumeCoverQueueProvider);
    final now = DateTime.now();
    final perDay = ReadingStats.perDay();
    final perBook = ReadingStats.perBook();
    final total = perDay.values.fold(0, (a, b) => a + b);
    final today = perDay[ReadingStats.dayKey(now)] ?? 0;
    final weekSum = [for (var i = 0; i < 7; i++) perDay[ReadingStats.dayKey(DateTime(now.year, now.month, now.day - i))] ?? 0].fold(0, (a, b) => a + b);
    final streak = readingStreak(perDay, now);
    final top = perBook.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    Widget card(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) => Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );

    Widget tile(IconData icon, String label, String value, {VoidCallback? onTap}) => Expanded(
      child: Material(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(height: 8),
                Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                Text(label, style: muted),
              ],
            ),
          ),
        ),
      ),
    );

    final bars = _bars(perDay, now);
    final maxBar = bars.fold(1, (a, b) => b.$2 > a ? b.$2 : a);
    final nonZero = bars.where((b) => b.$2 > 0);
    final avg = nonZero.isEmpty ? 0 : nonZero.fold(0, (a, b) => a + b.$2) ~/ nonZero.length;
    const chartH = 120.0;

    return Scaffold(
      appBar: AppBar(title: const Text('阅读统计')),
      body: total == 0 && ReadingStats.chapters == 0
          ? const StatePanel(title: '还没有阅读数据', detail: '读几章之后这里会出现统计。')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // 今天
                card(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('今天', style: muted),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '${(today / 60).ceil()}', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.primary)),
                                  TextSpan(text: ' 分钟', style: theme.textTheme.titleMedium),
                                ],
                              ),
                            ),
                            Text('近 7 天共 ${_duration(weekSum)}', style: muted),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Icon(Icons.local_fire_department_rounded, color: streak > 0 ? const Color(0xFFFF9500) : scheme.outline, size: 30),
                          Text('$streak 天', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text('连续阅读', style: muted),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 柱状图
                card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('阅读时长', style: theme.textTheme.titleMedium)),
                          SegmentedButton<int>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(visualDensity: VisualDensity.compact),
                            segments: const [ButtonSegment(value: 0, label: Text('周')), ButtonSegment(value: 1, label: Text('月')), ButtonSegment(value: 2, label: Text('年'))],
                            selected: {_range},
                            onSelectionChanged: (v) => setState(() {
                              _range = v.first;
                              _picked = null;
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 点了柱子显示那一天 / 那个月读了多久，没点时显示平均
                      Text(
                        _picked != null && _picked! < bars.length
                            ? '${bars[_picked!].$3} · ${bars[_picked!].$2 == 0 ? '没读' : _duration(bars[_picked!].$2)}'
                            : (avg == 0 ? '这段时间还没读' : '有阅读的${_range == 2 ? '月份' : '日子'}平均 ${_duration(avg)}，点柱子看每天'),
                        style: _picked == null ? muted : theme.textTheme.bodyMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: chartH + 20,
                        child: Stack(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final (i, (label, sec, _)) in bars.indexed)
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => setState(() => _picked = _picked == i ? null : i),
                                      child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: _range == 1 ? 1 : 4),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          AnimatedContainer(
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.easeOutCubic,
                                            height: (chartH - 2) * sec / maxBar + 2, // 2 是没读的日子也留的一条底
                                            decoration: BoxDecoration(
                                              color: _picked != null ? (_picked == i ? scheme.primary : scheme.primary.withValues(alpha: 0.25)) : (sec >= avg && avg > 0 ? scheme.primary : scheme.primary.withValues(alpha: 0.45)),
                                              borderRadius: BorderRadius.circular(_range == 1 ? 2 : 5),
                                            ),
                                          ),
                                          SizedBox(height: 20, child: Center(child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: theme.textTheme.labelSmall?.copyWith(color: _picked == i ? scheme.primary : scheme.onSurfaceVariant, fontWeight: _picked == i ? FontWeight.w700 : null)))),
                                        ],
                                      ),
                                    ),
                                    ),
                                  ),
                              ],
                            ),
                            // 平均线
                            if (avg > 0)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 20 + (chartH - 2) * avg / maxBar + 2,
                                child: IgnorePointer(child: Container(height: 1, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 阅读日历
                card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('阅读日历', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _Heatmap(perDay: perDay, now: now),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [tile(Icons.schedule_rounded, '累计阅读', _duration(total)), const SizedBox(width: 12), tile(Icons.article_outlined, '读过的章节', '${ReadingStats.chapters}')]),
                const SizedBox(height: 12),
                Row(
                  children: [
                    tile(Icons.menu_book_rounded, '读过的书', '${perBook.length}'),
                    const SizedBox(width: 12),
                    tile(Icons.auto_stories_rounded, '读完的卷 · 书籍墙', '${Volumes.allDone().length}', onTap: () => context.push(Routes.wall)),
                  ],
                ),
                const SizedBox(height: 24),
                Text('读得最久', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final e in top.take(20))
                  Builder(
                    builder: (context) {
                      final info = ReadingStats.info(e.key);
                      final img = queue.bookCover(e.key, info.img.isNotEmpty ? info.img : Wenku8Parser.coverUrl(e.key));
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => context.push(Routes.report(e.key)),
                        onLongPress: () => context.push(Routes.novel(e.key)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(width: 40, height: 56, child: CoverImage(img)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: Text(info.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge)),
                                        Text(_duration(e.value), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // 和读得最久的那本比的长度
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(value: e.value / top.first.value, minHeight: 5, color: scheme.primary, backgroundColor: scheme.primary.withValues(alpha: 0.12)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text('${ReadingStats.bookDays(e.key).length} 天 · ${ReadState.read(e.key).length} 章已读', style: muted),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 4),
                Text('点一本书看阅读报告，长按进详情', style: muted),
              ],
            ),
    );
  }
}

/// GitHub 那样的阅读日历：一列一周（周一在上），越往右越近，颜色越深读得越久。格子数按宽度放得下多少周算。
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.perDay, required this.now});

  final Map<String, int> perDay;
  final DateTime now;

  static const _cell = 13.0, _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    Color colorOf(int sec) {
      final m = sec / 60;
      if (m <= 0) return scheme.onSurface.withValues(alpha: 0.06);
      return scheme.primary.withValues(alpha: m < 15 ? 0.3 : (m < 30 ? 0.5 : (m < 60 ? 0.75 : 1)));
    }

    return LayoutBuilder(
      builder: (context, c) {
        final weeks = ((c.maxWidth + _gap) / (_cell + _gap)).floor().clamp(4, 53);
        final today = DateTime(now.year, now.month, now.day);
        final monday = today.subtract(Duration(days: today.weekday - 1));
        final start = monday.subtract(Duration(days: 7 * (weeks - 1)));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var w = 0; w < weeks; w++)
                  Padding(
                    padding: EdgeInsets.only(right: w < weeks - 1 ? _gap : 0),
                    child: Column(
                      children: [
                        for (var d = 0; d < 7; d++)
                          () {
                            final day = start.add(Duration(days: w * 7 + d));
                            return Padding(
                              padding: EdgeInsets.only(bottom: d < 6 ? _gap : 0),
                              child: Container(
                                width: _cell,
                                height: _cell,
                                decoration: BoxDecoration(
                                  color: day.isAfter(today) ? Colors.transparent : colorOf(perDay[ReadingStats.dayKey(day)] ?? 0),
                                  borderRadius: BorderRadius.circular(3),
                                  border: day == today ? Border.all(color: scheme.primary, width: 1.2) : null,
                                ),
                              ),
                            );
                          }(),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${start.month}月${start.day}日', style: small),
                const Spacer(),
                Text('少 ', style: small),
                for (final s in const [0, 600, 1200, 2400, 3600]) Container(width: 10, height: 10, margin: const EdgeInsets.only(left: 2), decoration: BoxDecoration(color: colorOf(s), borderRadius: BorderRadius.circular(2))),
                Text(' 多', style: small),
              ],
            ),
          ],
        );
      },
    );
  }
}
