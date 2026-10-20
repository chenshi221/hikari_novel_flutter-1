import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/bookshelf.dart';
import '../catalog.dart';
import '../data.dart';
import '../router.dart';
import '../session.dart';
import '../widgets.dart';

final bookshelfProvider = FutureProvider.autoDispose.family<Bookshelf, int>((ref, classId) => ref.watch(apiProvider).bookshelf(classId));

/// 书架：wenku8 的 6 个分组，长按进入多选，可批量移出或移到别的分组。
class BookshelfPage extends ConsumerWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sessionProvider) is! SessionLoggedIn) {
      return Scaffold(appBar: AppBar(title: const Text('书架')), body: const LoginPrompt(title: '登录后查看书架'));
    }
    return DefaultTabController(
      length: shelfNames.length,
      child: Scaffold(
        appBar: AppBar(title: const Text('书架'), bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final n in shelfNames) Tab(text: n)])),
        body: TabBarView(children: [for (var i = 0; i < shelfNames.length; i++) _Shelf(classId: i)]),
      ),
    );
  }
}

class _Shelf extends ConsumerStatefulWidget {
  const _Shelf({required this.classId});

  final int classId;

  @override
  ConsumerState<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends ConsumerState<_Shelf> with AutomaticKeepAliveClientMixin {
  final _selected = <String>{};

  @override
  bool get wantKeepAlive => true;

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
      _selected.clear();
      ref.invalidate(bookshelfProvider(widget.classId));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _move() async {
    final target = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < shelfNames.length; i++)
              if (i != widget.classId) ListTile(title: Text('移到「${shelfNames[i]}」'), onTap: () => Navigator.pop(context, i)),
          ],
        ),
      ),
    );
    if (target != null) await _act(() => ref.read(apiProvider).moveBooks(_selected.toList(), widget.classId, target));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final shelf = ref.watch(bookshelfProvider(widget.classId));
    final theme = Theme.of(context);
    return Column(
      children: [
        if (_selected.isNotEmpty)
          Material(
            color: theme.colorScheme.surfaceContainer,
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
                Text('已选 ${_selected.length} 本'),
                const Spacer(),
                TextButton(onPressed: _move, child: const Text('移动')),
                TextButton(onPressed: () => _act(() => ref.read(apiProvider).removeBooks(_selected.toList(), widget.classId)), child: const Text('移出书架')),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(bookshelfProvider(widget.classId).future),
            child: shelf.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => StatePanel(title: '书架加载失败', detail: e.toString(), onRetry: () => ref.invalidate(bookshelfProvider(widget.classId))),
              data: (data) => data.list.isEmpty
                  ? const StatePanel(title: '这个书架还是空的', detail: '在书籍详情页点"加入书架"后会出现在默认书架。')
                  : LayoutBuilder(
                      builder: (context, c) => GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridColumns(c.maxWidth), mainAxisSpacing: 20, crossAxisSpacing: 14, childAspectRatio: 0.52),
                        itemCount: data.list.length,
                        itemBuilder: (context, i) {
                          final book = data.list[i];
                          final picked = _selected.contains(book.bid);
                          void toggle() => setState(() => picked ? _selected.remove(book.bid) : _selected.add(book.bid));
                          return GestureDetector(
                            onLongPress: toggle,
                            child: NovelCard(
                              title: book.title,
                              aid: book.aid,
                              imageUrl: book.img,
                              onTap: _selected.isEmpty ? () => context.push(Routes.novel(book.aid)) : toggle,
                              badge: picked ? Icon(Icons.check_circle, color: theme.colorScheme.primary) : null,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
