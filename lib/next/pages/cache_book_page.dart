import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache.dart';
import '../widgets.dart';
import 'novel_page.dart';

/// 单本书的缓存管理：按卷列出章节，标出已缓存的，可选中若干章下载或删除。
class CacheBookPage extends ConsumerStatefulWidget {
  const CacheBookPage({super.key, required this.aid});

  final String aid;

  @override
  ConsumerState<CacheBookPage> createState() => _CacheBookPageState();
}

class _CacheBookPageState extends ConsumerState<CacheBookPage> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final novel = ref.watch(novelProvider(widget.aid));
    final task = ref.watch(downloadProvider)[widget.aid];
    return Scaffold(
      appBar: AppBar(title: const Text('缓存管理')),
      body: novel.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => StatePanel(title: '加载失败', detail: e.toString(), onRetry: () => ref.invalidate(novelProvider(widget.aid))),
        data: (data) {
          final all = data.catalogue.expand((v) => v.chapters).toList();
          final cached = ChapterCache.count(widget.aid);
          final running = task?.running ?? false;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: all.isEmpty ? 0 : cached / all.length, minHeight: 4, borderRadius: BorderRadius.circular(2)),
                    const SizedBox(height: 6),
                    Text('${data.detail.title} · 已缓存 $cached/${all.length} 章 · ${ChapterCache.sizeLabel(widget.aid)}${running ? ' · 下载中' : ''}${task?.error != null ? ' · ${task!.error}' : ''}'),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final v in data.catalogue)
                      ExpansionTile(
                        initiallyExpanded: data.catalogue.length == 1,
                        title: Text(v.title),
                        subtitle: Text('${v.chapters.where((c) => ChapterCache.has(widget.aid, c.cid)).length}/${v.chapters.length} 章已缓存'),
                        trailing: TextButton(
                          onPressed: () => setState(() {
                            final ids = v.chapters.map((c) => c.cid);
                            ids.every(_picked.contains) ? _picked.removeAll(ids) : _picked.addAll(ids);
                          }),
                          child: const Text('选卷'),
                        ),
                        children: [
                          for (final c in v.chapters)
                            CheckboxListTile(
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _picked.contains(c.cid),
                              onChanged: (_) => setState(() => _picked.contains(c.cid) ? _picked.remove(c.cid) : _picked.add(c.cid)),
                              title: Text(c.title),
                              secondary: ChapterCache.has(widget.aid, c.cid) ? const Icon(Icons.download_done, size: 18) : null,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      TextButton(onPressed: () => setState(() => _picked.length == all.length ? _picked.clear() : _picked.addAll(all.map((c) => c.cid))), child: Text(_picked.length == all.length ? '取消全选' : '全选')),
                      const Spacer(),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: _picked.isEmpty
                            ? null
                            : () async {
                                await ChapterCache.removeChapters(widget.aid, _picked);
                                setState(_picked.clear);
                              },
                        child: const Text('删除选中'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: running
                            ? () => ref.read(downloadProvider.notifier).cancel(widget.aid)
                            : (_picked.isEmpty ? null : () => ref.read(downloadProvider.notifier).start(widget.aid, data.detail.title, all.where((c) => _picked.contains(c.cid)).toList(), total: all.length)),
                        child: Text(running ? '暂停' : '下载选中'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
