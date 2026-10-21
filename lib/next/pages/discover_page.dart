import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/recommend_block.dart';
import '../catalog.dart';
import '../data.dart';
import '../router.dart';
import '../widgets.dart';

/// 发现：推荐 / 排行 / 分类 / 完结。
class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('发现'),
          actions: [IconButton(icon: const Icon(Icons.search), tooltip: '搜索', onPressed: () => context.push(Routes.search))],
          bottom: const TabBar(tabs: [Tab(text: '推荐'), Tab(text: '排行'), Tab(text: '分类'), Tab(text: '完结')]),
        ),
        body: const TabBarView(children: [_RecommendTab(), _RankingTab(), _CategoryTab(), _CompletedTab()]),
      ),
    );
  }
}

final _recommendProvider = FutureProvider.autoDispose<List<RecommendBlock>>((ref) => ref.watch(apiProvider).recommend());

class _RecommendTab extends ConsumerWidget {
  const _RecommendTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(_recommendProvider.future),
      child: ref
          .watch(_recommendProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => StatePanel(title: '加载失败', detail: e.toString(), error: e, onRetry: () => ref.invalidate(_recommendProvider)),
            data: (blocks) => ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final block in blocks) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(block.title, style: theme.textTheme.titleLarge),
                  ),
                  SizedBox(
                    height: 190,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: block.list.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => SizedBox(
                        width: 100,
                        child: NovelCard(title: block.list[i].title, aid: block.list[i].aid, imageUrl: block.list[i].imageUrl),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
    );
  }
}

class _Chips<T> extends StatelessWidget {
  const _Chips({required this.options, required this.value, required this.onChanged, required this.label});

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T) label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: options.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) => ChoiceChip(label: Text(label(options[i])), selected: options[i] == value, onSelected: (_) => onChanged(options[i])),
    ),
  );
}

class _RankingTab extends ConsumerStatefulWidget {
  const _RankingTab();

  @override
  ConsumerState<_RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends ConsumerState<_RankingTab> with AutomaticKeepAliveClientMixin {
  var _sort = rankings.first;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final api = ref.watch(apiProvider);
    return Column(
      children: [
        _Chips(options: rankings, value: _sort, label: (e) => e.$1, onChanged: (v) => setState(() => _sort = v)),
        Expanded(
          child: PagedNovelGrid(key: ValueKey(_sort), fetch: (page) => api.ranking(_sort.$2, page)),
        ),
      ],
    );
  }
}

class _CategoryTab extends ConsumerStatefulWidget {
  const _CategoryTab();

  @override
  ConsumerState<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends ConsumerState<_CategoryTab> with AutomaticKeepAliveClientMixin {
  var _tag = categoryTags.first;
  var _sort = categorySorts.first;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final api = ref.watch(apiProvider);
    return Column(
      children: [
        _Chips(options: categoryTags, value: _tag, label: (e) => e, onChanged: (v) => setState(() => _tag = v)),
        _Chips(options: categorySorts, value: _sort, label: (e) => e.$1, onChanged: (v) => setState(() => _sort = v)),
        Expanded(
          child: PagedNovelGrid(key: ValueKey((_tag, _sort)), fetch: (page) => api.category(_tag, _sort.$2, page)),
        ),
      ],
    );
  }
}

class _CompletedTab extends ConsumerWidget {
  const _CompletedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => PagedNovelGrid(fetch: ref.watch(apiProvider).completed);
}
