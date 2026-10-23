import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'bookmarks.dart';
import 'cache.dart';
import 'read_state.dart';

/// 章节列表左右滑能做的事（Mihon 的"章节滑动操作"）。
enum SwipeAct {
  off('关闭'),
  read('标记已读 / 未读'),
  bookmark('书签'),
  cache('缓存本章');

  const SwipeAct(this.label);

  final String label;
}

/// 右滑、左滑各自的动作，默认右滑标已读、左滑加书签（和 Mihon 一样）。
class SwipePrefs {
  const SwipePrefs(this.right, this.left);

  final SwipeAct right;
  final SwipeAct left;
}

class SwipePrefsController extends Notifier<SwipePrefs> {
  Box get _box => Hive.box('session');

  SwipeAct _get(String key, SwipeAct fallback) {
    final i = _box.get(key) as int?;
    return i == null || i < 0 || i >= SwipeAct.values.length ? fallback : SwipeAct.values[i];
  }

  @override
  SwipePrefs build() => SwipePrefs(_get('swipeRight', SwipeAct.read), _get('swipeLeft', SwipeAct.bookmark));

  void set({SwipeAct? right, SwipeAct? left}) {
    final next = SwipePrefs(right ?? state.right, left ?? state.left);
    _box.putAll({'swipeRight': next.right.index, 'swipeLeft': next.left.index});
    state = next;
  }
}

final swipePrefsProvider = NotifierProvider<SwipePrefsController, SwipePrefs>(SwipePrefsController.new);

/// 给一行章节加上左右滑。滑完动作执行后行自己弹回原位（[Dismissible] 的 confirmDismiss 返回 false），
/// 状态变了调 [onChanged] 让外面刷新。[onCache] 为空时"缓存"这个动作不可用（滑了没反应）。
class ChapterSwipe extends ConsumerWidget {
  const ChapterSwipe({super.key, required this.aid, required this.book, required this.cid, required this.title, required this.child, this.onChanged, this.onCache, this.enabled = true, this.backdrop});

  final String aid;
  final String book;
  final String cid;
  final String title;
  final Widget child;
  final VoidCallback? onChanged;
  final VoidCallback? onCache;
  final bool enabled;

  /// 行本身的底色：滑开时盖住后面的彩色背景（行是透明的会透出来）。默认取页面底色。
  final Color? backdrop;

  (IconData, String, Color) _look(SwipeAct a, ColorScheme s) => switch (a) {
    SwipeAct.read => ReadState.isRead(aid, cid) ? (Icons.remove_done, '标为未读', s.outline) : (Icons.done_all, '标为已读', const Color(0xFF2E9E5B)),
    SwipeAct.bookmark => Bookmarks.has(aid, cid, 0) ? (Icons.bookmark_remove_outlined, '取消书签', s.outline) : (Icons.bookmark_add_outlined, '加书签', const Color(0xFFE59A1F)),
    SwipeAct.cache => ChapterCache.has(aid, cid) ? (Icons.download_done, '已缓存', s.outline) : (Icons.download_outlined, '缓存本章', s.primary),
    SwipeAct.off => (Icons.block, '', Colors.transparent),
  };

  Future<void> _run(SwipeAct a) async {
    switch (a) {
      case SwipeAct.read:
        await ReadState.setRead(aid, [cid], !ReadState.isRead(aid, cid));
      case SwipeAct.bookmark:
        await Bookmarks.toggle(aid, book, cid, title, 0, '（章首书签）');
      case SwipeAct.cache:
        if (!ChapterCache.has(aid, cid)) onCache?.call();
      case SwipeAct.off:
        return;
    }
    HapticFeedback.lightImpact();
    onChanged?.call();
  }

  Widget _bg(SwipeAct a, ColorScheme s, Alignment align) {
    final (icon, label, color) = _look(a, s);
    return Container(
      color: color,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white), const SizedBox(width: 8), Text(label, style: const TextStyle(color: Colors.white))]),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(swipePrefsProvider);
    final scheme = Theme.of(context).colorScheme;
    final canCache = onCache != null;
    final right = p.right == SwipeAct.cache && !canCache ? SwipeAct.off : p.right;
    final left = p.left == SwipeAct.cache && !canCache ? SwipeAct.off : p.left;
    if (!enabled || (right == SwipeAct.off && left == SwipeAct.off)) return child;
    return Dismissible(
      key: ValueKey('swipe:$aid:$cid'),
      direction: right == SwipeAct.off ? DismissDirection.endToStart : (left == SwipeAct.off ? DismissDirection.startToEnd : DismissDirection.horizontal),
      dismissThresholds: const {DismissDirection.startToEnd: 0.3, DismissDirection.endToStart: 0.3},
      background: _bg(right, scheme, Alignment.centerLeft),
      secondaryBackground: _bg(left, scheme, Alignment.centerRight),
      confirmDismiss: (dir) async {
        await _run(dir == DismissDirection.startToEnd ? right : left);
        return false;
      },
      child: ColoredBox(color: backdrop ?? Scaffold.maybeOf(context)?.widget.backgroundColor ?? Theme.of(context).colorScheme.surface, child: child),
    );
  }
}
