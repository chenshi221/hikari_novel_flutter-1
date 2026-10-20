import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/wenku8/wenku8_parser.dart';
import '../../models/bookshelf.dart';
import '../env.dart';
import '../session.dart';
import '../widgets.dart';

/// wenku8 的书架编号 0~5，这里先只显示默认书架。
final bookshelfProvider = FutureProvider.autoDispose<Bookshelf>((ref) async {
  final client = ref.watch(wenku8ClientProvider);
  final urls = ref.watch(wenku8UrlsProvider);
  return Wenku8Parser.bookshelf(await client.getPage(urls.bookshelf(0)), 0);
});

class BookshelfPage extends ConsumerWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sessionProvider) is! SessionLoggedIn) {
      return Scaffold(appBar: AppBar(title: const Text('书架')), body: const LoginPrompt(title: '登录后查看书架'));
    }
    final shelf = ref.watch(bookshelfProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('书架')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(bookshelfProvider.future),
        child: shelf.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Message(title: '书架加载失败', detail: e.toString(), onRetry: () => ref.invalidate(bookshelfProvider)),
          data: (data) => data.list.isEmpty
              ? const _Message(title: '书架还是空的', detail: '在书籍详情页点"加入书架"后会出现在这里。')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.maxWidth / 132).floor().clamp(3, 8);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.52,
                      ),
                      itemCount: data.list.length,
                      itemBuilder: (context, i) {
                        final book = data.list[i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 3 / 4,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer),
                                  child: Image.network(
                                    displayImageUrl(book.img),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Icon(Icons.menu_book_outlined, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(height: 1.3)),
                          ],
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.detail, this.onRetry});

  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 放在可滚动容器里，保证下拉刷新可用
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 24),
          Center(
            child: OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ),
        ],
      ],
    );
  }
}
