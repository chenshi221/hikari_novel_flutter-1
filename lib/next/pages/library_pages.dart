import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../cache.dart';
import '../history.dart';
import '../router.dart';
import '../widgets.dart';

/// 浏览历史。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    final items = BrowsingHistory.all();
    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览历史'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                await BrowsingHistory.clear();
                setState(() {});
              },
              child: const Text('清空'),
            ),
        ],
      ),
      body: items.isEmpty
          ? const StatePanel(title: '还没有浏览记录')
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) => ListTile(
                leading: SizedBox(width: 40, height: 54, child: CoverImage(items[i].img)),
                title: Text(items[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => context.push(Routes.novel(items[i].aid)),
              ),
            ),
    );
  }
}

/// 离线缓存管理：看每本书缓存了多少章，可删除。
class CachePage extends StatefulWidget {
  const CachePage({super.key});

  @override
  State<CachePage> createState() => _CachePageState();
}

class _CachePageState extends State<CachePage> {
  @override
  Widget build(BuildContext context) {
    final books = ChapterCache.books().entries.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('离线缓存')),
      body: books.isEmpty
          ? const StatePanel(title: '还没有缓存', detail: '在书籍详情页点"缓存全本"。')
          : ListView(
              children: [
                for (final b in books)
                  ListTile(
                    title: Text(b.value.$1),
                    subtitle: Text('已缓存 ${ChapterCache.count(b.key)}/${b.value.$2} 章'),
                    onTap: () => context.push(Routes.novel(b.key)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await ChapterCache.remove(b.key);
                        setState(() {});
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
