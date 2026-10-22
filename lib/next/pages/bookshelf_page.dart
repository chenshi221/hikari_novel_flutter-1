import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../models/bookshelf.dart';
import '../catalog.dart';
import '../data.dart';
import '../progress.dart';
import '../read_state.dart';
import '../router.dart';
import '../session.dart';
import '../updates.dart';
import '../widgets.dart';

/// 常驻（不 autoDispose）：详情页判断"这本书在不在书架"、书架页都用同一份数据，只在刷新、加入、移出后才重新请求。
final bookshelfProvider = FutureProvider.family<Bookshelf, int>((ref, classId) => ref.watch(apiProvider).bookshelf(classId));

enum ShelfSort {
  site('默认'),
  name('名称'),
  lastRead('最近阅读'),
  updated('最近更新'),
  custom('自定义');

  const ShelfSort(this.label);

  final String label;
}

class _SortController extends Notifier<ShelfSort> {
  @override
  ShelfSort build() => ShelfSort.values[(Hive.box('session').get('shelfSort') as int?) ?? 0];

  void set(ShelfSort v) {
    Hive.box('session').put('shelfSort', v.index);
    state = v;
  }
}

final shelfSortProvider = NotifierProvider<_SortController, ShelfSort>(_SortController.new);

class _QueryController extends Notifier<String> {
  @override
  String build() => '';

  void set(String v) => state = v;
}

final shelfQueryProvider = NotifierProvider<_QueryController, String>(_QueryController.new);

List<BookshelfNovelInfo> _arrange(List<BookshelfNovelInfo> list, ShelfSort sort, String query, int classId) {
  final out = query.isEmpty ? [...list] : list.where((b) => b.title.toLowerCase().contains(query.toLowerCase())).toList();
  switch (sort) {
    case ShelfSort.site:
      break;
    case ShelfSort.name:
      out.sort((a, b) => a.title.compareTo(b.title));
    case ShelfSort.lastRead:
      out.sort((a, b) => ReadingProgress.lastRead(b.aid).compareTo(ReadingProgress.lastRead(a.aid)));
    case ShelfSort.updated:
      out.sort((a, b) => UpdateStore.updatedAt(b.aid).compareTo(UpdateStore.updatedAt(a.aid)));
    case ShelfSort.custom:
      final order = ((Hive.box('session').get('shelfOrder:$classId') as List?) ?? const []).cast<String>();
      int rank(BookshelfNovelInfo b) {
        final i = order.indexOf(b.aid);
        return i < 0 ? order.length : i;
      }

      out.sort((a, b) => rank(a).compareTo(rank(b)));
  }
  return out;
}

/// 书架：wenku8 的 6 个分组，支持搜索、5 种排序，长按多选后可批量移出或移到别的分组。
class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends ConsumerState<BookshelfPage> {
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    if (ref.watch(sessionProvider) is! SessionLoggedIn) {
      return Scaffold(appBar: AppBar(title: const Text('书架')), body: const LoginPrompt(title: '登录后查看书架'));
    }
    final sort = ref.watch(shelfSortProvider);
    return DefaultTabController(
      length: shelfNames.length,
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '在书架中搜索', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
                  onChanged: ref.read(shelfQueryProvider.notifier).set,
                )
              : const Text('书架'),
          actions: [
            IconButton(
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() => _searching = !_searching);
                if (!_searching) ref.read(shelfQueryProvider.notifier).set('');
              },
            ),
            PopupMenuButton<ShelfSort>(
              icon: const Icon(Icons.sort),
              tooltip: '排序',
              initialValue: sort,
              onSelected: ref.read(shelfSortProvider.notifier).set,
              itemBuilder: (_) => [for (final s in ShelfSort.values) CheckedPopupMenuItem(value: s, checked: s == sort, child: Text(s.label))],
            ),
          ],
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final n in shelfNames) Tab(text: n)]),
        ),
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
    final sort = ref.watch(shelfSortProvider);
    final query = ref.watch(shelfQueryProvider);
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
              error: (e, _) => StatePanel(title: '书架加载失败', detail: e.toString(), error: e, onRetry: () => ref.invalidate(bookshelfProvider(widget.classId))),
              data: (data) {
                final books = _arrange(data.list, sort, query, widget.classId);
                if (data.list.isEmpty) return const StatePanel(title: '这个书架还是空的', detail: '在书籍详情页点"加入书架"后会出现在默认书架。');
                if (books.isEmpty) return const StatePanel(title: '没有匹配的书');
                if (sort == ShelfSort.custom && query.isEmpty) return _reorderable(books);
                return LayoutBuilder(
                  builder: (context, c) => GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    gridDelegate: novelGridDelegate(c.maxWidth),
                    itemCount: books.length,
                    itemBuilder: (context, i) {
                      final book = books[i];
                      final picked = _selected.contains(book.bid);
                      // 未读章数：上次检查更新时记下的总章数减去读过的章数
                      final total = UpdateStore.knownCounts()[book.aid] ?? 0;
                      final unread = total - ReadState.read(book.aid).length;
                      void toggle() => setState(() => picked ? _selected.remove(book.bid) : _selected.add(book.bid));
                      return GestureDetector(
                        onLongPress: toggle,
                        child: NovelCard(
                          title: book.title,
                          aid: book.aid,
                          imageUrl: book.img,
                          onTap: _selected.isEmpty ? () => context.push(Routes.novel(book.aid)) : toggle,
                          badge: picked ? Icon(Icons.check_circle, color: theme.colorScheme.primary) : (unread > 0 && total > 0 ? Badge(label: Text('$unread')) : null),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 自定义排序：列表形式，拖动右侧把手调整，顺序记在本机。
  Widget _reorderable(List<BookshelfNovelInfo> books) => ReorderableListView.builder(
    padding: const EdgeInsets.only(bottom: 24),
    itemCount: books.length,
    onReorderItem: (from, to) {
      final list = [...books];
      list.insert(to, list.removeAt(from));
      Hive.box('session').put('shelfOrder:${widget.classId}', [for (final b in list) b.aid]);
      setState(() {});
    },
    itemBuilder: (context, i) => ListTile(
      key: ValueKey(books[i].bid),
      leading: SizedBox(width: 40, height: 54, child: CoverImage(books[i].img)),
      title: Text(books[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
      onTap: () => context.push(Routes.novel(books[i].aid)),
    ),
  );
}
