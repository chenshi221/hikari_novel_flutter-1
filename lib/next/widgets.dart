import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/novel_cover.dart';
import '../data/wenku8/wenku8_parser.dart';
import 'data.dart' show PageResult;
import 'env.dart';
import 'router.dart';
import 'session.dart';

/// 游客看到需要账号的内容时显示的提示，点按钮再去登录。
class LoginPrompt extends StatelessWidget {
  const LoginPrompt({super.key, required this.title, this.detail = '登录轻小说文库账号后即可使用。'});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.push(Routes.login), child: const Text('去登录')),
          ],
        ),
      ),
    );
  }
}

/// 错误 / 空状态。出错时给"重试"，没登录时额外给"去登录"。可滚动，保证下拉刷新可用。
class StatePanel extends ConsumerWidget {
  const StatePanel({super.key, required this.title, this.detail, this.onRetry});

  final String title;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final guest = ref.watch(sessionProvider) is! SessionLoggedIn;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            detail!,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: 24),
          Center(child: OutlinedButton(onPressed: onRetry, child: const Text('重试'))),
        ],
        if (onRetry != null && guest) ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton(onPressed: () => context.push(Routes.login), child: const Text('可能需要登录，去登录')),
          ),
        ],
      ],
    );
  }
}

class CoverImage extends StatelessWidget {
  const CoverImage(this.url, {super.key});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(color: scheme.surfaceContainer),
        child: SizedBox.expand(
          child: Image.network(
            displayImageUrl(url),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(Icons.menu_book_outlined, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// 封面 + 书名，点击进入详情。
class NovelCard extends StatelessWidget {
  const NovelCard({super.key, required this.title, required this.aid, this.imageUrl, this.onTap, this.badge});

  final String title;
  final String aid;
  final String? imageUrl;
  final VoidCallback? onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap ?? () => context.push(Routes.novel(aid)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(fit: StackFit.expand, children: [CoverImage(imageUrl ?? Wenku8Parser.coverUrl(aid)), if (badge != null) Positioned(top: 6, right: 6, child: badge!)]),
          ),
          const SizedBox(height: 8),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(height: 1.3)),
        ],
      ),
    );
  }
}

int gridColumns(double width) => (width / 132).floor().clamp(3, 8);

SliverGridDelegate _gridDelegate(double width) =>
    SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridColumns(width), mainAxisSpacing: 20, crossAxisSpacing: 14, childAspectRatio: 0.52);

/// 分页的书籍网格：下拉刷新，滑到底自动加载下一页。[fetch] 变化（用 [Key] 区分）时整体重新加载。
class PagedNovelGrid extends ConsumerStatefulWidget {
  const PagedNovelGrid({super.key, required this.fetch});

  final Future<PageResult> Function(int page) fetch;

  @override
  ConsumerState<PagedNovelGrid> createState() => _PagedNovelGridState();
}

class _PagedNovelGridState extends ConsumerState<PagedNovelGrid> {
  final _items = <NovelCover>[];
  int _page = 0;
  int _maxPage = 1;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (!reset && _page >= _maxPage)) return;
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });
    try {
      final next = reset ? 1 : _page + 1;
      final result = await widget.fetch(next);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(result.items);
        _page = next;
        _maxPage = result.maxPage == 0 ? next : result.maxPage;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _error != null ? StatePanel(title: '加载失败', detail: _error.toString(), onRetry: () => _load(reset: true)) : const StatePanel(title: '没有内容'),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) _load();
          return false;
        },
        child: LayoutBuilder(
          builder: (context, c) => GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: _gridDelegate(c.maxWidth),
            itemCount: _items.length,
            itemBuilder: (context, i) => NovelCard(title: _items[i].title, aid: _items[i].aid, imageUrl: _items[i].imageUrl),
          ),
        ),
      ),
    );
  }
}
