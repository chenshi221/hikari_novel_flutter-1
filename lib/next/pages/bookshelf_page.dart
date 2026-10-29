import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../app_prefs.dart';
import '../bookmarks.dart';
import '../cache.dart';
import '../image_cache.dart';
import '../library.dart';
import '../progress.dart';
import '../read_state.dart';
import '../router.dart';
import '../session.dart';
import '../settings.dart';
import '../theme.dart';
import '../theme_doodle.dart';
import '../theme_squire.dart';
import '../updates.dart';
import '../volumes.dart';
import '../widgets.dart';
import 'categories_page.dart';
import 'cover_picker_page.dart';
import 'volumes_page.dart';

enum ShelfSort {
  added('加入时间'),
  name('名称'),
  lastRead('最近阅读'),
  updated('最近更新'),
  unread('未读章数'),
  total('总章数'),
  random('随机'),
  custom('自定义');

  const ShelfSort(this.label);

  final String label;
}

/// 书架的排序、筛选、显示方式，记在本地。筛选是三态：0 不限 1 必须满足 2 必须不满足（Mihon 那样）。
class ShelfOptions {
  const ShelfOptions({this.sort = ShelfSort.added, this.reverse = false, this.display = 3, this.unread = 0, this.started = 0, this.cached = 0, this.bookmarked = 0, this.completed = 0});

  final ShelfSort sort;

  /// 排序方向反过来（每种排序都有自己默认的方向）
  final bool reverse;

  /// 0 网格 1 紧凑网格 2 列表 3 卷册（一本书画成一摞卷）
  final int display;

  /// 筛选：有未读 / 已开始读 / 有缓存 / 有书签 / 已完结
  final int unread;
  final int started;
  final int cached;
  final int bookmarked;
  final int completed;

  bool get filtering => unread + started + cached + bookmarked + completed > 0;

  ShelfOptions copyWith({ShelfSort? sort, bool? reverse, int? display, int? unread, int? started, int? cached, int? bookmarked, int? completed}) => ShelfOptions(
    sort: sort ?? this.sort,
    reverse: reverse ?? this.reverse,
    display: display ?? this.display,
    unread: unread ?? this.unread,
    started: started ?? this.started,
    cached: cached ?? this.cached,
    bookmarked: bookmarked ?? this.bookmarked,
    completed: completed ?? this.completed,
  );

  Map<String, Object> toMap() => {'sort': sort.index, 'reverse': reverse, 'display': display, 'unread': unread, 'started': started, 'cached': cached, 'bookmarked': bookmarked, 'completed': completed};

  static ShelfOptions fromMap(Map m) => ShelfOptions(
    sort: ShelfSort.values[((m['sort'] as int?) ?? 0).clamp(0, ShelfSort.values.length - 1)],
    reverse: (m['reverse'] as bool?) ?? false,
    display: (m['display'] as int?) ?? 3,
    unread: (m['unread'] as int?) ?? 0,
    started: (m['started'] as int?) ?? 0,
    cached: (m['cached'] as int?) ?? 0,
    bookmarked: (m['bookmarked'] as int?) ?? 0,
    completed: (m['completed'] as int?) ?? 0,
  );
}

class _OptionsController extends Notifier<ShelfOptions> {
  Box get _box => Hive.box('session');

  @override
  ShelfOptions build() {
    final saved = _box.get('shelfOpts');
    if (saved is Map) return ShelfOptions.fromMap(saved);
    // 旧版本分开存的：排序、显示方式、三个开关筛选
    final f = ((_box.get('shelfFilter') as List?) ?? const []).cast<String>();
    final sort = (_box.get('shelfSort') as int?) ?? 0;
    return ShelfOptions(
      sort: ShelfSort.values[sort.clamp(0, ShelfSort.values.length - 1)],
      display: (_box.get('shelfDisplay') as int?) ?? 3,
      unread: f.contains('unread') ? 1 : 0,
      cached: f.contains('cached') ? 1 : 0,
      completed: f.contains('done') ? 1 : 0,
    );
  }

  void set(ShelfOptions v) {
    _box.put('shelfOpts', v.toMap());
    state = v;
  }
}

/// 这个标签页用的筛选 / 排序 / 显示：开了"每个标签单独设置"就用它自己存的，没存过用全局的。
ShelfOptions shelfOptionsFor(ShelfOptions base, String tabId) {
  if (!AppPrefs.read(P.perCat, false)) return base;
  final m = AppPrefs.read<Object?>('shelf.tab.$tabId', null);
  return m is Map ? ShelfOptions.fromMap(m) : base;
}

/// 卷册模式封面右边留给后面几卷封面边的宽度（最多 3 张，每张错开 5）
const _edges = 15.0;

/// 书架正在多选：外面的底部导航据此收起，让位给多选的操作条
final shelfSelecting = ValueNotifier<bool>(false);

/// 书架正在搜索：返回键先关搜索，外面不提示退出
final shelfSearching = ValueNotifier<bool>(false);

final shelfOptionsProvider = NotifierProvider<_OptionsController, ShelfOptions>(_OptionsController.new);

class _QueryController extends Notifier<String> {
  @override
  String build() => '';

  void set(String v) => state = v;
}

final shelfQueryProvider = NotifierProvider<_QueryController, String>(_QueryController.new);

/// 三态筛选：0 不限，1 必须满足，2 必须不满足
bool _tri(int state, bool Function() test) => state == 0 || test() == (state == 1);

/// 某个标签页里的书：默认是全部，连载 / 完结按状态分（同名的自建分类并进来），其余是自建分类里的。
Iterable<LibBook> _booksIn(LibraryState lib, String tabId) {
  bool inNamed(LibBook b, String name) => lib.cats.any((c) => c.name == name && b.cats.contains(c.id));
  return lib.books.values.where((b) => switch (tabId) {
    '' => true,
    _ongoingTab => !b.done && !inNamed(b, '完结') || inNamed(b, '连载'),
    _doneTab => b.done || inNamed(b, '完结'),
    final id => b.cats.contains(id),
  });
}

/// 某个标签页里有几本书（分类管理页用）
int booksInTab(LibraryState lib, String tabId) => _booksIn(lib, tabId).length;

bool _started(String aid) => ReadingProgress.of(aid) != null || ReadState.read(aid).isNotEmpty;

/// 未读章数：上次检查更新时记下的总章数减去读过的章数。
int _unread(String aid) {
  final total = UpdateStore.knownCounts()[aid] ?? 0;
  return total == 0 ? 0 : (total - ReadState.read(aid).length).clamp(0, total);
}

List<LibBook> _arrange(Iterable<LibBook> list, ShelfOptions o, String query, String catId) {
  final q = query.toLowerCase();
  final out = list
      .where((b) => q.isEmpty || b.shown.toLowerCase().contains(q) || b.title.toLowerCase().contains(q))
      .where((b) => _tri(o.unread, () => _unread(b.aid) > 0) && _tri(o.started, () => _started(b.aid)) && _tri(o.cached, () => ChapterCache.count(b.aid) > 0) && _tri(o.bookmarked, () => Bookmarks.all(b.aid).isNotEmpty) && _tri(o.completed, () => b.done))
      .toList();
  switch (o.sort) {
    case ShelfSort.added:
      out.sort((a, b) => b.added.compareTo(a.added));
    case ShelfSort.name:
      out.sort((a, b) => a.shown.compareTo(b.shown));
    case ShelfSort.lastRead:
      out.sort((a, b) => ReadingProgress.lastRead(b.aid).compareTo(ReadingProgress.lastRead(a.aid)));
    case ShelfSort.updated:
      out.sort((a, b) => UpdateStore.updatedAt(b.aid).compareTo(UpdateStore.updatedAt(a.aid)));
    case ShelfSort.unread:
      out.sort((a, b) => _unread(b.aid).compareTo(_unread(a.aid)));
    case ShelfSort.total:
      out.sort((a, b) => (UpdateStore.knownCounts()[b.aid] ?? 0).compareTo(UpdateStore.knownCounts()[a.aid] ?? 0));
    case ShelfSort.random:
      final seed = AppPrefs.read('shelf.seed', 1);
      out.sort((a, b) => Object.hash(a.aid, seed).compareTo(Object.hash(b.aid, seed)));
    case ShelfSort.custom:
      final order = ((Hive.box('session').get('shelfOrder:lib:$catId') as List?) ?? const []).cast<String>();
      int rank(LibBook b) {
        final i = order.indexOf(b.aid);
        return i < 0 ? order.length : i;
      }

      out.sort((a, b) => rank(a).compareTo(rank(b)));
  }
  return o.reverse ? out.reversed.toList() : out;
}

/// 书架：本地书库，分类是本地的（Mihon 那样），网站书架只在下拉刷新、打开 App 时同步一次。
/// 长按多选后可批量设置分类、移出书架。
class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

/// 自动分组的标签 id：按书是否完结实时分，不存在书里
const _ongoingTab = 'auto:ongoing';
const _doneTab = 'auto:done';
const _autoNames = {'连载', '完结'};

/// 全部标签（含隐藏的）：默认（全部书）、连载、完结，再加自己建的分类；顺序按拖动存的 shelfTabOrder，没存过的排后面。
List<LibCategory> allShelfTabs(List<LibCategory> cats) {
  // 自己建过同名的分类（比如"完结"）时合并：不再单独显示，里面的书并入自动标签（见 [_Shelf]）
  final all = [const LibCategory('', '默认'), const LibCategory(_ongoingTab, '连载'), const LibCategory(_doneTab, '完结'), ...cats.where((c) => !_autoNames.contains(c.name))];
  final order = ((Hive.box('session').get('shelfTabOrder') as List?) ?? const []).cast<String>();
  int rank(LibCategory c) {
    final i = order.indexOf(c.id);
    return i < 0 ? order.length : i;
  }

  return [...all]..sort((a, b) => rank(a).compareTo(rank(b))); // sort 稳定，没存过的保持原顺序
}

/// 书架上显示的标签：去掉隐藏的；全隐藏了就留第一个
List<LibCategory> shelfTabs(List<LibCategory> cats) {
  final all = allShelfTabs(cats);
  final hidden = AppPrefs.readList(P.hiddenTabs);
  final shown = all.where((c) => !hidden.contains(c.id)).toList();
  return shown.isEmpty ? all.take(1).toList() : shown;
}

/// 自建分类里和自动标签同名的不单独显示（并进自动标签）
bool isMergedCategory(LibCategory c) => _autoNames.contains(c.name);

class _BookshelfPageState extends ConsumerState<BookshelfPage> with TickerProviderStateMixin {
  bool _searching = false;

  void _setSearching(bool v) {
    _searching = v;
    // 晚一拍改通知器：同一次返回键里，外层 PopScope 不管先后都读到旧值
    Future.microtask(() => shelfSearching.value = _searching);
  }

  TabController? _tc;
  List<String> _ids = [];
  String _shown = ''; // 标签栏上次滚到的标签
  final _keys = <String, GlobalKey>{};
  final _stripKey = GlobalKey();
  int _measureRetries = 0;
  final _tabScroll = ScrollController();

  Box get _box => Hive.box('session');

  @override
  void dispose() {
    shelfSearching.value = false;
    _tc?.dispose();
    _tabScroll.dispose();
    super.dispose();
  }

  /// 第 i 个标签里文字那一段在标签栏里的位置（左边、宽度）；还没排好版时返回 null
  (double, double)? _labelRect(List<LibCategory> tabs, int i) {
    final strip = _stripKey.currentContext?.findRenderObject() as RenderBox?;
    final box = _keys[tabs[i].id]?.currentContext?.findRenderObject() as RenderBox?;
    if (strip == null || box == null || !box.attached || !box.hasSize) return null;
    final left = box.localToGlobal(Offset.zero, ancestor: strip).dx;
    return (left + 14, box.size.width - 28); // 去掉左右内边距，下划线和字一样宽
  }

  /// 标签变了（新增 / 删除 / 拖动）就换一个 TabController，停在原来的标签上。
  TabController _controller(List<String> ids) {
    if (!listEquals(ids, _ids) || _tc == null) {
      final first = _tc == null;
      final cur = first ? AppPrefs.read(P.lastTab, '') : _ids[_tc!.index.clamp(0, _ids.length - 1)];
      final old = _tc;
      _tc = TabController(length: ids.length, vsync: this, initialIndex: math.max(0, ids.indexOf(cur)));
      _ids = ids;
      _tc!.addListener(_scrollToTab);
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      if (first) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _scrollToTab() : null); // 标签栏滚到上次的标签
    }
    return _tc!;
  }

  void _scrollToTab() {
    final tc = _tc!;
    if (tc.indexIsChanging) return;
    final id = _ids[tc.index];
    if (AppPrefs.read(P.lastTab, '') != id) AppPrefs.write(P.lastTab, id);
    if (id == _shown) return;
    _shown = id;
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 200), alignment: 0.5);
  }

  /// 标签栏：点一下切换，长按拖动调整顺序
  PreferredSizeWidget _tabStrip(List<LibCategory> tabs, TabController tc, LibraryState lib) {
    final counts = AppPrefs.read(P.tabCounts, false);
    final theme = Theme.of(context);
    return PreferredSize(
      preferredSize: const Size.fromHeight(44),
      // 横向的滚动列表要有确定的高度，不然 AppBar 里量不出来、整条顶栏画不出
      child: SizedBox(
        height: 44,
        // 下划线和字色跟着滑动的进度走（和发现页的系统标签栏一样），不是切换完才跳过去
        child: AnimatedBuilder(
          animation: Listenable.merge([tc.animation!, _tabScroll]),
          builder: (context, _) {
            final at = tc.animation!.value.clamp(0.0, tabs.length - 1.0);
            final lo = at.floor(), hi = at.ceil();
            // 标签滑出屏幕时量不到（列表只排眼前的），就先用另一头的位置
            final ra = _labelRect(tabs, lo), rb = _labelRect(tabs, hi);
            final a = ra ?? rb, b = rb ?? ra;
            final t = at - lo;
            // 第一次进来时标签还没排好版：下一帧再画一次（最多重试几次，免得一直重建）
            if (a == null && _measureRetries++ < 3) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() {}) : null);
            return Stack(
              key: _stripKey,
              children: [
                ReorderableListView.builder(
                  scrollController: _tabScroll,
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: tabs.length,
                  proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                  onReorderItem: (from, to) {
                    final ids = [for (final c in tabs) c.id];
                    ids.insert(to, ids.removeAt(from));
                    // 隐藏的标签留在原位，可见的按新顺序填回它们占的位置
                    final all = [for (final c in allShelfTabs(lib.cats)) c.id];
                    var k = 0;
                    _box.put('shelfTabOrder', [for (final id in all) ids.contains(id) ? ids[k++] : id]);
                    setState(() {});
                  },
                  itemBuilder: (context, i) {
                    final c = tabs[i];
                    final near = (1 - (at - i).abs()).clamp(0.0, 1.0); // 1 = 正在这个标签
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(c.id),
                      index: i,
                      child: InkWell(
                        onTap: () => tc.animateTo(i),
                        child: Container(
                          key: _keys.putIfAbsent(c.id, GlobalKey.new),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            counts ? '${c.name} ${_booksIn(lib, c.id).length}' : c.name,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color.lerp(theme.colorScheme.onSurfaceVariant, theme.colorScheme.primary, near)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (a != null && b != null)
                  Positioned(
                    left: a.$1 + (b.$1 - a.$1) * t,
                    width: a.$2 + (b.$2 - a.$2) * t,
                    bottom: 0,
                    height: 3,
                    child: IgnorePointer(
                      child: DecoratedBox(decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: const BorderRadius.vertical(top: Radius.circular(3)))),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String get _curTab => _ids.isEmpty || _tc == null ? '' : _ids[_tc!.index.clamp(0, _ids.length - 1)];

  void _showOptions() {
    final tabId = _curTab;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          ref.watch(appPrefsProvider);
          final o = shelfOptionsFor(ref.watch(shelfOptionsProvider), tabId);
          final perCat = AppPrefs.read(P.perCat, false);
          final colsKey = MediaQuery.orientationOf(context) == Orientation.landscape ? P.colsLandscape : P.colsPortrait;
          void set(ShelfOptions v) => perCat ? ref.read(appPrefsProvider.notifier).set('shelf.tab.$tabId', v.toMap()) : ref.read(shelfOptionsProvider.notifier).set(v);
          final theme = Theme.of(context);
          Widget title(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 8), child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)));
          Widget tri(String label, int v, ShelfOptions Function(int) apply) => FilterChip(
            avatar: v == 0 ? null : Icon(v == 1 ? Icons.check : Icons.block, size: 16),
            label: Text(label, style: v == 2 ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
            selected: v != 0,
            showCheckmark: false,
            onSelected: (_) => set(apply((v + 1) % 3)), // 不限 → 必须满足 → 必须不满足
          );
          final tabName = allShelfTabs(ref.read(libraryProvider).cats).firstWhere((c) => c.id == tabId, orElse: () => const LibCategory('', '默认')).name;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (perCat) Text('以下设置只对「$tabName」生效', style: theme.textTheme.bodySmall),
                  title('筛选'),
                  Text('点按切换：满足 / 不满足 / 不限', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      tri('有未读', o.unread, (v) => o.copyWith(unread: v)),
                      tri('已开始读', o.started, (v) => o.copyWith(started: v)),
                      tri('有缓存', o.cached, (v) => o.copyWith(cached: v)),
                      tri('有书签', o.bookmarked, (v) => o.copyWith(bookmarked: v)),
                      tri('已完结', o.completed, (v) => o.copyWith(completed: v)),
                    ],
                  ),
                  title('排序'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in ShelfSort.values)
                        ChoiceChip(
                          avatar: o.sort == s && s != ShelfSort.custom && s != ShelfSort.random ? Icon(o.reverse ? Icons.arrow_upward : Icons.arrow_downward, size: 16) : null,
                          label: Text(s.label),
                          selected: o.sort == s,
                          showCheckmark: false,
                          // 再点一次当前的排序：方向反过来；随机再点一次换一批
                          onSelected: (_) {
                            if (s == ShelfSort.random) ref.read(appPrefsProvider.notifier).set('shelf.seed', DateTime.now().millisecondsSinceEpoch & 0xFFFF);
                            set(o.sort == s ? o.copyWith(reverse: !o.reverse) : o.copyWith(sort: s, reverse: false));
                          },
                        ),
                    ],
                  ),
                  title('显示'),
                  SegmentedButton<int>(
                    segments: const [ButtonSegment(value: 0, label: Text('网格')), ButtonSegment(value: 1, label: Text('紧凑')), ButtonSegment(value: 2, label: Text('列表')), ButtonSegment(value: 3, label: Text('卷册'))],
                    selected: {o.display},
                    onSelectionChanged: (v) => set(o.copyWith(display: v.first)),
                  ),
                  if (o.display != 2) ...[
                    const SizedBox(height: 8),
                    // 就是设置里的书架列数（竖屏、横屏分开记），这里只放常用的几种
                    SegmentedButton<int>(
                      emptySelectionAllowed: true,
                      segments: const [ButtonSegment(value: 0, label: Text('自动')), ButtonSegment(value: 3, label: Text('3 列')), ButtonSegment(value: 4, label: Text('4 列'))],
                      selected: {AppPrefs.read(colsKey, 0)}.intersection(const {0, 3, 4}),
                      onSelectionChanged: (v) => v.isEmpty ? null : ref.read(appPrefsProvider.notifier).set(colsKey, v.first),
                    ),
                  ],
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('未读章数角标'), value: AppPrefs.read(P.unreadBadge, true), onChanged: (v) => ref.read(appPrefsProvider.notifier).set(P.unreadBadge, v)),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('已缓存章数角标'), value: AppPrefs.read(P.cacheBadge, false), onChanged: (v) => ref.read(appPrefsProvider.notifier).set(P.cacheBadge, v)),
                  title('更多'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.casino_outlined),
                    title: const Text('随机打开一本'),
                    onTap: () {
                      final books = _booksIn(ref.read(libraryProvider), tabId).toList();
                      if (books.isEmpty) return;
                      final b = books[math.Random().nextInt(books.length)];
                      Navigator.pop(context);
                      this.context.push(o.display == 3 ? Routes.volumes(b.aid) : Routes.novel(b.aid));
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.refresh),
                    title: Text('检查「$tabName」的更新'),
                    onTap: () {
                      final aids = _booksIn(ref.read(libraryProvider), tabId).map((b) => b.aid).toSet();
                      Navigator.pop(context);
                      ref.read(updateProvider.notifier).refresh(only: aids);
                      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('正在检查 ${aids.length} 本的更新')));
                    },
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
    ref.watch(appPrefsProvider);
    final tabs = shelfTabs(lib.cats);
    final tc = _controller([for (final c in tabs) c.id]);
    final o = shelfOptionsFor(ref.watch(shelfOptionsProvider), _curTab);
    final scene = appPalettes[ref.watch(paletteProvider)].scene;
    // 插画主题：顶栏加高，标题和按钮压在插画的天空上，下面的分类标签仍在页面底色上
    final appBar = AppBar(
      foregroundColor: scene ? RuinsColors.of(context).ink : null,
      flexibleSpace: scene ? Column(children: [Expanded(child: RuinsScene(animate: AppPrefs.read(P.sceneMotion, true), horizon: 0.86, ceiling: 0.5)), const SizedBox(height: 44)]) : null,
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
            setState(() => _setSearching(!_searching));
            if (!_searching) ref.read(shelfQueryProvider.notifier).set('');
          },
        ),
        IconButton(tooltip: '筛选、排序、显示', icon: Icon(Icons.filter_list, color: o.filtering ? Theme.of(context).colorScheme.primary : null), onPressed: _showOptions),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: context.push,
          itemBuilder: (_) => const [
            PopupMenuItem(value: Routes.wall, child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.collections_bookmark_outlined), title: Text('书籍墙'))),
            PopupMenuItem(value: Routes.categories, child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.label_outline), title: Text('管理分类'))),
          ],
        ),
      ],
      bottom: scene ? PreferredSize(preferredSize: const Size.fromHeight(44 + 64), child: Column(children: [const SizedBox(height: 64), _tabStrip(tabs, tc, lib)])) : _tabStrip(tabs, tc, lib),
    );
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _setSearching(false));
        ref.read(shelfQueryProvider.notifier).set('');
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false, // 外层主界面已经让开了键盘，这里再让一次，书架只剩上面一小截
        appBar: appBar,
        body: TabBarView(key: ObjectKey(tc), controller: tc, children: [for (final c in tabs) _Shelf(key: ValueKey(c.id), catId: c.id)]),
      ),
    );
  }
}

class _Shelf extends ConsumerStatefulWidget {
  const _Shelf({super.key, required this.catId});

  /// 分类 id：空串是"默认"（全部的书），[_ongoingTab] / [_doneTab] 按是否完结分，其余是自己建的分类
  final String catId;

  @override
  ConsumerState<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends ConsumerState<_Shelf> with AutomaticKeepAliveClientMixin {
  final _selected = <String>{};
  static final _selecting = <String>{}; // 哪几个标签页正在多选

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 这个标签里的封面先从磁盘读进内存，往下滑时直接就有，不用等读盘
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(imageStoreProvider).warm([for (final b in _booksIn(ref.read(libraryProvider), widget.catId)) _cover(b)]);
    });
  }

  void _syncSelecting() {
    _selected.isEmpty ? _selecting.remove(widget.catId) : _selecting.add(widget.catId);
    shelfSelecting.value = _selecting.isNotEmpty;
  }

  @override
  void dispose() {
    _selecting.remove(widget.catId);
    Future.microtask(() => shelfSelecting.value = _selecting.isNotEmpty);
    super.dispose();
  }

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

  /// 书架上的封面是第一卷的卷封面，所以换的是第一卷的
  Future<void> _pickCover() async {
    final vols = Volumes.of(_selected.first);
    if (vols.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先打开一次这本书的详情，目录加载后才能选封面')));
      return;
    }
    await pickVolumeCover(context, _selected.first, vols.first);
    if (mounted) setState(_selected.clear);
  }

  /// 改书架上显示的名字（只在本机，网站上不变），留空恢复原名
  Future<void> _rename() async {
    final b = ref.read(libraryProvider).books[_selected.first];
    if (b == null) return;
    final controller = TextEditingController(text: b.shown);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('显示名称'),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: b.title), onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定'))],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose()); // 退出动画还在用它，晚一帧再释放
    if (name == null) return;
    await ref.read(libraryProvider.notifier).rename(b.aid, name);
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
    ref.watch(appPrefsProvider); // 书架设置（角标、列数、每个标签单独设置）变了就重建
    final o = shelfOptionsFor(ref.watch(shelfOptionsProvider), widget.catId);
    final query = ref.watch(shelfQueryProvider);
    ref.watch(updateProvider); // 检查完更新后刷新未读数
    ref.watch(volumeChangesProvider); // 取到卷封面后换上
    final theme = Theme.of(context);
    final inCat = query.isEmpty ? _booksIn(lib, widget.catId) : lib.books.values; // 搜索时不分标签，整个书架里找
    final books = _arrange(inCat, o, query, widget.catId);

    final Widget body;
    if (lib.books.isEmpty) {
      body = const StatePanel(title: '书架还是空的', detail: '在书籍详情页点"加入书架"。登录后下拉可以把网站上的书架同步过来。');
    } else if (books.isEmpty) {
      body = StatePanel(title: inCat.isEmpty ? '这个分类还没有书' : (query.isEmpty ? '没有符合条件的书' : '书架里没有找到「$query」'), detail: inCat.isEmpty && !widget.catId.startsWith('auto:') ? '在书架长按书本，选"分类"放进来。' : null);
    } else if (o.sort == ShelfSort.custom && query.isEmpty && !o.filtering) {
      body = _reorderable(books);
    } else if (o.display == 2) {
      body = ListView.builder(padding: const EdgeInsets.only(bottom: 24), itemCount: books.length, itemBuilder: (context, i) => _listTile(books[i]));
    } else if (o.display == 3) {
      body = LayoutBuilder(
        builder: (context, c) {
          final n = _cols(context) ?? (c.maxWidth / 140).floor().clamp(2, 8);
          final w = (c.maxWidth - 32 - 14 * (n - 1)) / n;
          return GridView.builder(
            scrollCacheExtent: const ScrollCacheExtent.viewport(1), // 上下各多备一屏，快速滑动时封面也已经解码好
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            // 一格 = 封面（右边留出后面几卷的边）+ 下面两行字
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: n, mainAxisSpacing: 16, crossAxisSpacing: 14, childAspectRatio: w / ((w - _edges) / kCoverAspect + 46)),
            itemCount: books.length,
            itemBuilder: (context, i) => _stackTile(books[i]),
          );
        },
      );
    } else {
      body = LayoutBuilder(
        builder: (context, c) => GridView.builder(
          scrollCacheExtent: const ScrollCacheExtent.viewport(1),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          gridDelegate: o.display == 1
              ? SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _cols(context) ?? (c.maxWidth / 104).floor().clamp(3, 10), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.72)
              : (_cols(context) == null ? novelGridDelegate(c.maxWidth) : SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _cols(context)!, mainAxisSpacing: 20, crossAxisSpacing: 14, childAspectRatio: 0.52)),
          itemCount: books.length,
          itemBuilder: (context, i) => _gridTile(books[i], compact: o.display == 1),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSelecting();
    });
    return PopScope(
      canPop: _selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear); // 返回键先退出多选
      },
      child: Column(
        children: [
          Expanded(child: RefreshIndicator(onRefresh: _refresh, child: body)),
          if (_selected.isNotEmpty)
            Material(
              elevation: 3,
              color: theme.colorScheme.surfaceContainer,
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
                    Expanded(child: Text('${_selected.length} 本', maxLines: 1, softWrap: false, overflow: TextOverflow.fade)),
                    TextButton(onPressed: () => setState(() => _selected.addAll(books.map((b) => b.aid))), child: const Text('全选')),
                    if (_selected.length == 1) TextButton(onPressed: _rename, child: const Text('改名')),
                    if (_selected.length == 1) TextButton(onPressed: _pickCover, child: const Text('封面')),
                    TextButton(onPressed: _setCats, child: const Text('分类')),
                    TextButton(onPressed: _remove, child: const Text('移出')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _cover(LibBook b) => ref.read(volumeCoverQueueProvider).bookCover(b.aid, b.img);

  void _toggle(String aid) {
    // 第一本长按时重一点的震动，之后点选轻一点
    _selected.isEmpty ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
    setState(() => _selected.contains(aid) ? _selected.remove(aid) : _selected.add(aid));
  }

  void _tap(LibBook b) => _selected.isEmpty ? context.push(Routes.novel(b.aid)) : _toggle(b.aid);

  /// 封面右下角的"继续阅读"：直接回到上次读的位置（读过才有）。
  Widget? _resume(LibBook b) {
    final p = ReadingProgress.of(b.aid);
    if (p == null || _selected.isNotEmpty || !AppPrefs.read(P.resumeButton, true)) return null;
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
    final n = AppPrefs.read(P.unreadBadge, true) ? _unread(b.aid) : 0;
    final c = AppPrefs.read(P.cacheBadge, false) ? ChapterCache.count(b.aid) : 0;
    if (n == 0 && c == 0) return null;
    // 插画主题用燕尾小旗代替圆角标，角色主题用蜡笔描边的小圆
    final scene = appPalettes[ref.read(paletteProvider)].scene;
    final doodle = CharacterArt.of(context) != null;
    final scheme = Theme.of(context).colorScheme;
    Widget badge(String t, Color bg, Color fg, {bool plain = false}) => scene
        ? PennantBadge(t, color: bg, textColor: fg)
        : doodle
        ? DoodleBadge(t, color: bg, textColor: fg)
        : Badge(label: Text(t), backgroundColor: plain ? null : bg);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c > 0) badge('$c', scheme.secondary, scene ? RuinsColors.day.ink : Colors.white),
        if (c > 0 && n > 0) const SizedBox(width: 3),
        if (n > 0) badge('$n', scheme.primary, scheme.onPrimary, plain: true),
      ],
    );
  }

  /// 自己设了列数就用它（竖屏、横屏分开设），0 是自动
  int? _cols(BuildContext context) {
    final n = AppPrefs.read(MediaQuery.orientationOf(context) == Orientation.landscape ? P.colsLandscape : P.colsPortrait, 0);
    return n == 0 ? null : n;
  }

  Widget _gridTile(LibBook b, {required bool compact}) {
    final resume = _resume(b);
    final badge = _badge(b);
    if (!compact) {
      return GestureDetector(
        onLongPress: () => _toggle(b.aid),
        child: NovelCard(title: b.shown, aid: b.aid, imageUrl: _cover(b), onTap: () => _tap(b), badge: badge, action: resume),
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
          Positioned(left: 6, right: resume == null ? 6 : 40, bottom: 6, child: Text(b.shown, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.25))),
          if (badge != null) Positioned(top: 6, right: 6, child: badge),
          if (resume != null) Positioned(right: 0, bottom: 0, child: resume),
        ],
      ),
    );
  }

  /// 卷册：第一卷封面在最前，右边露出后面几卷真封面的一窄条边（卷越多条数越多，单卷没有），书名和读到第几卷在封面下面。
  Widget _stackTile(LibBook b) {
    final vols = Volumes.of(b.aid);
    final at = readingVolume(b.aid);
    final allDone = vols.isNotEmpty && vols.every((v) => Volumes.done(b.aid).containsKey(v.title));
    final badge = _badge(b);
    final queue = ref.read(volumeCoverQueueProvider);
    final behind = [for (final v in vols.skip(1).take(stackEdges(vols.length))) queue.volCover(b.aid, v, b.img)];
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _selected.isEmpty ? context.push(Routes.volumes(b.aid)) : _toggle(b.aid),
      onLongPress: () => _toggle(b.aid),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = math.min(c.maxWidth - _edges, c.maxHeight * kCoverAspect);
                final h = w / kCoverAspect;
                return Stack(
                  clipBehavior: Clip.none, // 后面几卷的边在封面右边、Stack 外面
                  children: [
                    // 整叠放进 Hero：点开时一起飞过去放大
                    SizedBox(
                      width: w,
                      height: h,
                      child: Hero(tag: 'vols:${b.aid}', flightShuttleBuilder: volumeHeroShuttle, child: VolumeStack(cover: _cover(b), behind: behind)),
                    ),
                    if (badge != null) Positioned(top: 6, right: 6, child: badge),
                    if (vols.length == 1)
                      Positioned(
                        left: 6,
                        top: h - 6 - 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                          child: const Text('单卷', style: TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(b.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Text(
            vols.isEmpty ? '还没有分卷信息' : [if (allDone) '已读完' else if (at >= 0) '读到第 ${at + 1} 卷', '共 ${vols.length} 卷'].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
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
      title: Text(b.shown, maxLines: 2, overflow: TextOverflow.ellipsis),
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
      title: Text(books[i].shown, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
      onTap: () => context.push(Routes.novel(books[i].aid)),
    ),
  );
}
