import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/cat_volume.dart';
import '../cache.dart';
import '../data.dart';
import '../pages/bookshelf_page.dart' show bookshelfProvider;
import '../progress.dart';
import '../read_state.dart';
import '../router.dart';
import '../session.dart';
import '../widgets.dart';

final novelProvider = FutureProvider.autoDispose.family<NovelPage, String>((ref, aid) => ref.watch(apiProvider).novel(aid));

/// 这本书在哪个书架里：返回 bid（移出书架要用），不在书架里为 null。游客直接返回 null。
final shelfEntryProvider = FutureProvider.autoDispose.family<String?, String>((ref, aid) async {
  if (ref.watch(sessionProvider) is! SessionLoggedIn) return null;
  // 书架数据是共享的、常驻的（bookshelfProvider），不用每开一本书的详情页就重新请求 6 个书架页
  for (var classId = 0; classId < 6; classId++) {
    final shelf = await ref.watch(bookshelfProvider(classId).future);
    final hit = shelf.list.where((e) => e.aid == aid).firstOrNull;
    if (hit != null) return hit.bid;
  }
  return null;
});

class NovelPageView extends ConsumerWidget {
  const NovelPageView({super.key, required this.aid});

  final String aid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novel = ref.watch(novelProvider(aid));
    return Scaffold(
      appBar: AppBar(),
      body: novel.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => StatePanel(title: '加载失败', detail: e.toString(), error: e, onRetry: () => ref.invalidate(novelProvider(aid))),
        data: (data) => _Body(aid: aid, data: data),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.aid, required this.data});

  final String aid;
  final NovelPage data;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  String get aid => widget.aid;
  NovelPage get data => widget.data;

  /// 打开别的页面，回来时刷新（阅读进度、已读状态会变）。
  Future<void> _open(String route, {Object? extra}) async {
    await context.push(route, extra: extra);
    if (mounted) setState(() {});
  }

  void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _toggleShelf(String? bid) async {
    if (ref.read(sessionProvider) is! SessionLoggedIn) {
      context.push(Routes.login);
      return;
    }
    final api = ref.read(apiProvider);
    try {
      if (bid == null) {
        await api.addToBookshelf(aid);
      } else {
        await api.removeFromBookshelf(bid);
      }
      ref.invalidate(bookshelfProvider);
      ref.invalidate(shelfEntryProvider(aid));
    } catch (e) {
      if (mounted) _snack(context, e.toString());
    }
  }

  String? _firstCid() => data.catalogue.expand((v) => v.chapters).firstOrNull?.cid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = data.detail;
    final entry = ref.watch(shelfEntryProvider(aid));
    final progress = ReadingProgress.of(aid);
    final all = data.catalogue.expand((v) => v.chapters).toList();
    final read = ReadState.read(aid);
    final unread = all.where((c) => !read.contains(c.cid)).length;
    final latest = all.reversed.take(3).toList();
    final startCid = progress?.cid ?? _firstCid();
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, height: 150, child: CoverImage(d.imgUrl)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => context.push(Routes.searchAuthor(d.author)),
                    child: Text(d.author, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.primary)),
                  ),
                  const SizedBox(height: 6),
                  Text([d.status, if (d.isDelisted) '已下架' else '更新于 ${d.lastUpdate}'].join(' · '), style: muted),
                  if (d.heat != null) Text('热度 ${d.heat}　上升 ${d.trending}', style: muted),
                  if (d.isAnimated) Text('已动画化', style: muted),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final t in d.tags.where((e) => e.isNotEmpty)) Chip(label: Text(t))]),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: startCid == null ? null : () => _open(Routes.reader(aid, startCid)),
                child: Text(progress == null ? '开始阅读' : '继续阅读'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: entry.isLoading ? null : () => _toggleShelf(entry.value),
                child: Text(entry.value == null ? '加入书架' : '移出书架'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () async {
                  if (ref.read(sessionProvider) is! SessionLoggedIn) {
                    context.push(Routes.login);
                    return;
                  }
                  try {
                    final msg = await ref.read(apiProvider).vote(aid);
                    if (context.mounted) _snack(context, msg.isEmpty ? '已投票' : msg);
                  } catch (e) {
                    if (context.mounted) _snack(context, e.toString());
                  }
                },
                icon: const Icon(Icons.thumb_up_outlined),
                label: const Text('推荐'),
              ),
            ),
            Expanded(
              child: TextButton.icon(onPressed: () => _open(Routes.comments(aid)), icon: const Icon(Icons.forum_outlined), label: const Text('书评')),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('${siteBase(ref.read(nodeProvider))}/book/$aid.htm'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('网页'),
              ),
            ),
          ],
        ),
        _DownloadRow(aid: aid, title: d.title, data: data),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('已读 ${all.length - unread} / ${all.length} 章 · 未读 $unread 章', style: theme.textTheme.titleSmall)),
                    TextButton(onPressed: () => _open(Routes.report(aid)), child: const Text('阅读报告')),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: all.isEmpty ? 0 : (all.length - unread) / all.length, minHeight: 4, borderRadius: BorderRadius.circular(2)),
                if (latest.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('最新章节', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  for (final c in latest)
                    InkWell(
                      onTap: () => _open(Routes.reader(aid, c.cid)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(read.contains(c.cid) ? Icons.check_circle_outline : Icons.fiber_manual_record, size: 12, color: read.contains(c.cid) ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: read.contains(c.cid) ? muted : null)),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('简介', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(d.introduce.trim().isEmpty ? '暂无简介' : d.introduce.trim(), style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
        const SizedBox(height: 20),
        Text('目录', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final CatVolume v in data.catalogue)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: data.catalogue.length == 1 || v.chapters.any((c) => c.cid == progress?.cid),
            title: Text(v.title),
            children: [
              for (final c in v.chapters)
                ListTile(
                  dense: true,
                  leading: read.contains(c.cid) ? Icon(Icons.check, size: 16, color: theme.colorScheme.onSurfaceVariant) : null,
                  title: Text(
                    c.title,
                    style: c.cid == progress?.cid
                        ? TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)
                        : (read.contains(c.cid) ? TextStyle(color: theme.colorScheme.onSurfaceVariant) : null),
                  ),
                  trailing: c.cid == progress?.cid ? Text('读到这里', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)) : null,
                  onTap: () => _open(Routes.reader(aid, c.cid)),
                ),
            ],
          ),
      ],
    );
  }
}

/// 缓存全本：显示已缓存章数，下载中显示进度并可取消。
class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({required this.aid, required this.title, required this.data});

  final String aid;
  final String title;
  final NovelPage data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = data.catalogue.expand((v) => v.chapters).toList();
    final task = ref.watch(downloadProvider)[aid];
    final cached = task?.done ?? ChapterCache.count(aid);
    final running = task?.running ?? false;
    return Row(
      children: [
        Expanded(
          child: Text(
            running ? '正在缓存 $cached/${chapters.length}' : (task?.error ?? '已缓存 $cached/${chapters.length} 章'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        if (running)
          TextButton(onPressed: () => ref.read(downloadProvider.notifier).cancel(aid), child: const Text('暂停'))
        else ...[
          TextButton(onPressed: cached >= chapters.length ? null : () => ref.read(downloadProvider.notifier).start(aid, title, chapters, img: data.detail.imgUrl), child: const Text('缓存全本')),
          TextButton(onPressed: () => context.push(Routes.cacheBook(aid)), child: const Text('管理')),
        ],
      ],
    );
  }
}
