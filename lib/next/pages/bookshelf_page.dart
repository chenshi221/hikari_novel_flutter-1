import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../cache.dart';
import '../library.dart';
import '../progress.dart';
import '../read_state.dart';
import '../router.dart';
import '../session.dart';
import '../updates.dart';
import '../volumes.dart';
import '../widgets.dart';
import 'categories_page.dart';

enum ShelfSort {
  added('加入时间'),
  name('名称'),
  lastRead('最近阅读'),
  updated('最近更新'),
  unread('未读章数'),
  custom('自定义');

  const ShelfSort(this.label);

  final String label;
}

/// 书架的排序、筛选、显示方式，记在本地。
class ShelfOptions {
  const ShelfOptions({this.sort = ShelfSort.added, this.display = 0, this.unread = false, this.cached = false, this.done = false});

  final ShelfSort sort;

  /// 0 网格 1 紧凑网格 2 列表
  final int display;

  /// 筛选：只看有未读 / 有缓存 / 已完结
  final bool unread;
  final bool cached;
  final bool done;

  bool get filtering => unread || cached || done;

  ShelfOptions copyWith({ShelfSort? sort, int? display, bool? unread, bool? cached, bool? done}) =>
      ShelfOptions(sort: sort ?? this.sort, display: display ?? this.display, unread: unread ?? this.unread, cached: cached ?? this.cached, done: done ?? this.done);
}

class _OptionsController extends Notifier<ShelfOptions> {
  Box get _box => Hive.box('session');

  @override
  ShelfOptions build() {
    final f = ((_box.get('shelfFilter') as List?) ?? const []).cast<String>();
    final sort = (_box.get('shelfSort') as int?) ?? 0;
    return ShelfOptions(sort: ShelfSort.values[sort.clamp(0, ShelfSort.values.length - 1)], display: (_box.get('shelfDisplay') as int?) ?? 0, unread: f.contains('unread'), cached: f.contains('cached'), done: f.contains('done'));
  }

  void set(ShelfOptions v) {
    _box.putAll({
      'shelfSort': v.sort.index,
      'shelfDisplay': v.display,
      'shelfFilter': [if (v.unread) 'unread', if (v.cached) 'cached', if (v.done) 'done'],
    });
    state = v;
  }
}

final shelfOptionsProvider = NotifierProvider<_OptionsController, ShelfOptions>(_OptionsController.new);

class _QueryController extends Notifier<String> {
  @override
  String build() => '';

  void set(String v) => state = v;
}

final shelfQueryProvider = NotifierProvider<_QueryController, String>(_QueryController.new);

/// 未读章数：上次检查更新时记下的总章数减去读过的章数。
int _unread(String aid) {
  final total = UpdateStore.knownCounts()[aid] ?? 0;
  return total == 0 ? 0 : (total - ReadState.read(aid).length).clamp(0, total);
}

List<LibBook> _arrange(Iterable<LibBook> list, ShelfOptions o, String query, String catId) {
  final q = query.toLowerCase();
  final out = list
      .where((b) => q.isEmpty || b.title.toLowerCase().contains(q))
      .where((b) => (!o.unread || _unread(b.aid) > 0) && (!o.cached || ChapterCache.count(b.aid) > 0) && (!o.done || b.done))
      .toList();
  switch (o.sort) {
    case ShelfSort.added:
      out.sort((a, b) => b.added.compareTo(a.added));
    case ShelfSort.name:
      out.sort((a, b) => a.title.compareTo(b.title));
    case ShelfSort.lastRead:
      out.sort((a, b) => ReadingProgress.lastRead(b.aid).compareTo(ReadingProgress.lastRead(a.aid)));
    case ShelfSort.updated:
      out.sort((a, b) => UpdateStore.updatedAt(b.aid).compareTo(UpdateStore.updatedAt(a.aid)));
    case ShelfSort.unread:
      out.sort((a, b) => _unread(b.aid).compareTo(_unread(a.aid)));
    case ShelfSort.custom:
      final order = ((Hive.box('session').get('shelfOrder:lib:$catId') as List?) ?? const []).cast<String>();
      int rank(LibBook b) {
        final i = order.indexOf(b.aid);
        return i < 0 ? order.length : i;
      }

      out.sort((a, b) => rank(a).compareTo(rank(b)));
  }
  return out;
}

/// 书架：本地书库，分类是本地的（Mihon 那样），网站书架只在下拉刷新、打开 App 时同步一次。
/// 长按多选后可批量设置分类、移出书架。
class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends ConsumerState<BookshelfPage> {
  bool _searching = false;

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final o = ref.watch(shelfOptionsProvider);
          void set(ShelfOptions v) => ref.read(shelfOptionsProvider.notifier).set(v);
          final theme = Theme.of(context);
          Widget title(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 8), child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)));
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title('筛选'),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(label: const Text('有未读'), selected: o.unread, onSelected: (v) => set(o.copyWith(unread: v))),
                      FilterChip(label: const Text('有缓存'), selected: o.cached, onSelected: (v) => set(o.copyWith(cached: v))),
                      FilterChip(label: const Text('已完结'), selected: o.done, onSelected: (v) => set(o.copyWith(done: v))),
                    ],
                  ),
                  title('排序'),
                  Wrap(spacing: 8, runSpacing: 8, children: [for (final s in ShelfSort.values) ChoiceChip(label: Text(s.label), selected: o.sort == s, onSelected: (_) => set(o.copyWith(sort: s)))]),
                  title('显示'),
                  SegmentedButton<int>(
                    segments: const [ButtonSegment(value: 0, label: Text('网格')), ButtonSegment(value: 1, label: Text('紧凑')), ButtonSegment(value: 2, label: Text('列表'))],
                    selected: {o.display},
                    onSelectionChanged: (v) => set(o.copyWith(display: v.first)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final o = ref.watch(shelfOptionsProvider);
    // "默认"放没分类的书；有别的分类且默认里没书时不显示它
    final tabs = [
      if (lib.cats.isEmpty || lib.books.values.any((b) => b.cats.isEmpty)) const LibCategory('', '默认'),
      ...lib.cats,
    ];
    final appBar = AppBar(
      title: _searching
          ? TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: '在书架中搜索', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
              onChanged: ref.read(shelfQueryProvider.notifier).set,
            )
          : Text('书架 · ${lib.books.length}'),
      actions: [
        IconButton(
          icon: Icon(_searching ? Icons.close : Icons.search),
          onPressed: () {
            setState(() => _searching = !_searching);
            if (!_searching) ref.read(shelfQueryProvider.notifier).set('');
          },
        ),
        IconButton(tooltip: '筛选、排序、显示', icon: Icon(Icons.filter_list, color: o.filtering ? Theme.of(context).colorScheme.primary : null), onPressed: _showOptions),
        IconButton(tooltip: '管理分类', icon: const Icon(Icons.label_outline), onPressed: () => context.push(Routes.categories)),
      ],
      bottom: tabs.length > 1 ? TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final c in tabs) Tab(text: c.name)]) : null,
    );
    if (tabs.length == 1) return Scaffold(appBar: appBar, body: const _Shelf(catId: ''));
    return DefaultTabController(
      key: ValueKey(tabs.map((c) => c.id).join(',')),
      length: tabs.length,
      child: Scaffold(appBar: appBar, body: TabBarView(children: [for (final c in tabs) _Shelf(catId: c.id)])),
    );
  }
}

class _Shelf extends ConsumerStatefulWidget {
  const _Shelf({required this.catId});

  /// 分类 id，空串是"默认"（没放进任何分类的书）
  final String catId;

  @override
  ConsumerState<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends ConsumerState<_Shelf> with AutomaticKeepAliveClientMixin {
  final _selected = <String>{};

  @override
  bool get wantKeepAlive => true;

  /// 下拉：和网站书架同步，再检查更新。
  Future<void> _refresh() async {
    if (ref.read(sessionProvider) is! SessionLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录后才能和网站书架同步，本地书架照常可用')));
      return;
    }
    final err = await ref.read(libraryProvider.notifier).sync(force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err == null ? '已和网站书架同步，书架共 ${ref.read(libraryProvider).books.length} 本' : '同步网站书架失败：$err')));
    ref.read(updateProvider.notifier).refresh();
  }

  Future<void> _setCats() async {
    final lib = ref.read(libraryProvider);
    if (lib.cats.isEmpty) {
      context.push(Routes.categories);
      return;
    }
    // 只选了一本时预先勾上它现在的分类
    final initial = _selected.length == 1 ? lib.books[_selected.first]?.cats ?? const <String>[] : const <String>[];
    final cats = await pickCategories(context, lib.cats, initial);
    if (cats == null) return;
    await ref.read(libraryProvider.notifier).setCats(_selected, cats);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _remove() async {
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移出 $n 本书？'),
        content: const Text('登录时会一起从网站书架移出。阅读进度和缓存不会删。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('移出'))],
      ),
    );
    if (ok != true) return;
    await ref.read(libraryProvider.notifier).remove(_selected);
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lib = ref.watch(libraryProvider);
    final o = ref.watch(shelfOptionsProvider);
    final query = ref.watch(shelfQueryProvider);
    ref.watch(updateProvider); // 检查完更新后刷新未读数
    ref.watch(volumeChangesProvider); // 取到卷封面后换上
    final theme = Theme.of(context);
    final inCat = lib.books.values.where((b) => widget.catId.isEmpty ? b.cats.isEmpty : b.cats.contains(widget.catId));
    final books = _arrange(inCat, o, query, widget.catId);

    final Widget body;
    if (lib.books.isEmpty) {
      body = const StatePanel(title: '书架还是空的', detail: '在书籍详情页点"加入书架"。登录后下拉可以把网站上的书架同步过来。');
    } else if (books.isEmpty) {
      body = StatePanel(title: inCat.isEmpty ? '这个分类还没有书' : '没有符合条件的书', detail: inCat.isEmpty ? '在书架长按书本，选"分类"放进来。' : null);
    } else if (o.sort == ShelfSort.custom && query.isEmpty && !o.filtering) {
      body = _reorderable(books);
    } else if (o.display == 2) {
      body = ListView.builder(padding: const EdgeInsets.only(bottom: 24), itemCount: books.length, itemBuilder: (context, i) => _listTile(books[i]));
    } else {
      body = LayoutBuilder(
        builder: (context, c) => GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          gridDelegate: o.display == 1
              ? SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: (c.maxWidth / 104).floor().clamp(3, 10), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.72)
              : novelGridDelegate(c.maxWidth),
          itemCount: books.length,
          itemBuilder: (context, i) => _gridTile(books[i], compact: o.display == 1),
        ),
      );
    }

    return Column(
      children: [
        if (_selected.isNotEmpty)
          Material(
            color: theme.colorScheme.surfaceContainer,
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
                Expanded(child: Text('已选 ${_selected.length} 本')),
                TextButton(onPressed: () => setState(() => _selected.addAll(books.map((b) => b.aid))), child: const Text('全选')),
                TextButton(onPressed: _setCats, child: const Text('分类')),
                TextButton(onPressed: _remove, child: const Text('移出')),
              ],
            ),
          ),
        Expanded(child: RefreshIndicator(onRefresh: _refresh, child: body)),
      ],
    );
  }

  /// 封面用正在读的那卷（没读过用最新一卷）的卷封面；还没取到、或者这卷没插图时用书的封面。
  String _cover(LibBook b) {
    final vols = Volumes.of(b.aid);
    if (vols.isEmpty) return b.img;
    return ref.read(volumeCoverQueueProvider).get(b.aid, vols[Volumes.shelfVolume(b.aid)]) ?? b.img;
  }

  void _toggle(String aid) => setState(() => _selected.contains(aid) ? _selected.remove(aid) : _selected.add(aid));

  void _tap(LibBook b) => _selected.isEmpty ? context.push(Routes.novel(b.aid)) : _toggle(b.aid);

  /// 封面右下角的"继续阅读"：直接回到上次读的位置（读过才有）。
  Widget? _resume(LibBook b) {
    final p = ReadingProgress.of(b.aid);
    if (p == null || _selected.isNotEmpty) return null;
    return IconButton.filledTonal(
      tooltip: '继续阅读',
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      icon: const Icon(Icons.play_arrow),
      onPressed: () => context.push(Routes.reader(b.aid, p.cid)),
    );
  }

  Widget? _badge(LibBook b) {
    if (_selected.contains(b.aid)) return Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary);
    final n = _unread(b.aid);
    return n > 0 ? Badge(label: Text('$n')) : null;
  }

  Widget _gridTile(LibBook b, {required bool compact}) {
    final resume = _resume(b);
    final badge = _badge(b);
    if (!compact) {
      return GestureDetector(
        onLongPress: () => _toggle(b.aid),
        child: NovelCard(title: b.title, aid: b.aid, imageUrl: _cover(b), onTap: () => _tap(b), badge: badge, action: resume),
      );
    }
    // 紧凑：书名压在封面底部的渐变上
    return GestureDetector(
      onLongPress: () => _toggle(b.aid),
      onTap: () => _tap(b),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverImage(_cover(b)),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
            ),
          ),
          Positioned(left: 6, right: resume == null ? 6 : 40, bottom: 6, child: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.25))),
          if (badge != null) Positioned(top: 6, right: 6, child: badge),
          if (resume != null) Positioned(right: 0, bottom: 0, child: resume),
        ],
      ),
    );
  }

  Widget _listTile(LibBook b) {
    final p = ReadingProgress.of(b.aid);
    final n = _unread(b.aid);
    return ListTile(
      selected: _selected.contains(b.aid),
      leading: SizedBox(width: 40, height: 54, child: CoverImage(_cover(b))),
      title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text([if (n > 0) '未读 $n 章', if (ChapterCache.count(b.aid) > 0) '已缓存 ${ChapterCache.count(b.aid)} 章', if (b.done) '已完结', if (p == null) '还没读'].join(' · ')),
      trailing: _selected.contains(b.aid) ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : _resume(b),
      onTap: () => _tap(b),
      onLongPress: () => _toggle(b.aid),
    );
  }

  /// 自定义排序：列表形式，拖动右侧把手调整，每个分类单独记顺序。
  Widget _reorderable(List<LibBook> books) => ReorderableListView.builder(
    padding: const EdgeInsets.only(bottom: 24),
    itemCount: books.length,
    onReorderItem: (from, to) {
      final list = [...books];
      list.insert(to, list.removeAt(from));
      Hive.box('session').put('shelfOrder:lib:${widget.catId}', [for (final b in list) b.aid]);
      setState(() {});
    },
    itemBuilder: (context, i) => ListTile(
      key: ValueKey(books[i].aid),
      leading: SizedBox(width: 40, height: 54, child: CoverImage(_cover(books[i]))),
      title: Text(books[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
      onTap: () => context.push(Routes.novel(books[i].aid)),
    ),
  );
}
