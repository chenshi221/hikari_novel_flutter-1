import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../bookmarks.dart';
import '../router.dart';
import '../widgets.dart';
import 'updates_page.dart';

/// 所有书签，按书分组；点一下回到书签位置。
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = Bookmarks.all();
    final books = <String, List<Bookmark>>{};
    for (final b in all) {
      books.putIfAbsent(b.aid, () => []).add(b);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('书签')),
      body: all.isEmpty
          ? const StatePanel(title: '还没有书签', detail: '阅读时点底部栏的书签，或选中文字后点"加书签"。')
          : ListView(
              children: [
                for (final e in books.entries) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(e.value.first.book, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary))),
                  for (final b in e.value)
                    Dismissible(
                      key: ValueKey('${b.aid}${b.cid}${b.offset}'),
                      onDismissed: (_) async {
                        await Bookmarks.remove(b);
                        setState(() {});
                      },
                      background: Container(color: theme.colorScheme.error.withValues(alpha: 0.15)),
                      child: ListTile(
                        title: Text(b.excerpt.isEmpty ? b.chapter : b.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${b.chapter} · ${dayLabel(b.time)} ${hhmm(b.time)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        // 位置随路由传过去，不覆盖真正的阅读进度
                        onTap: () => context.push(Routes.reader(b.aid, b.cid), extra: b.offset),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
