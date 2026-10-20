import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/cat_volume.dart';
import '../data.dart';
import '../progress.dart';
import '../router.dart';
import '../session.dart';
import '../widgets.dart';

final novelProvider = FutureProvider.autoDispose.family<NovelPage, String>((ref, aid) => ref.watch(apiProvider).novel(aid));

/// 这本书在哪个书架里：返回 bid（移出书架要用），不在书架里为 null。游客直接返回 null。
final shelfEntryProvider = FutureProvider.autoDispose.family<String?, String>((ref, aid) async {
  if (ref.watch(sessionProvider) is! SessionLoggedIn) return null;
  final api = ref.watch(apiProvider);
  for (var classId = 0; classId < 6; classId++) {
    final shelf = await api.bookshelf(classId);
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
        error: (e, _) => StatePanel(title: '加载失败', detail: e.toString(), onRetry: () => ref.invalidate(novelProvider(aid))),
        data: (data) => _Body(aid: aid, data: data),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.aid, required this.data});

  final String aid;
  final NovelPage data;

  void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _toggleShelf(BuildContext context, WidgetRef ref, String? bid) async {
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
      ref.invalidate(shelfEntryProvider(aid));
    } catch (e) {
      if (context.mounted) _snack(context, e.toString());
    }
  }

  String? _firstCid() => data.catalogue.expand((v) => v.chapters).firstOrNull?.cid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final d = data.detail;
    final entry = ref.watch(shelfEntryProvider(aid));
    final progress = ReadingProgress.of(aid);
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
                onPressed: startCid == null ? null : () => context.push(Routes.reader(aid, startCid)),
                child: Text(progress == null ? '开始阅读' : '继续阅读'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: entry.isLoading ? null : () => _toggleShelf(context, ref, entry.value),
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
              child: TextButton.icon(onPressed: () => context.push(Routes.comments(aid)), icon: const Icon(Icons.forum_outlined), label: const Text('书评')),
            ),
          ],
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
                  title: Text(c.title, style: c.cid == progress?.cid ? TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600) : null),
                  onTap: () => context.push(Routes.reader(aid, c.cid)),
                ),
            ],
          ),
      ],
    );
  }
}
