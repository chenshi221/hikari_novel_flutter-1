import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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

/// 给一行章节加上左右滑。滑过触发线松手就执行，行自己弹回原位（见 [_SwipeRow]），
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(swipePrefsProvider);
    final scheme = Theme.of(context).colorScheme;
    final canCache = onCache != null;
    final right = p.right == SwipeAct.cache && !canCache ? SwipeAct.off : p.right;
    final left = p.left == SwipeAct.cache && !canCache ? SwipeAct.off : p.left;
    if (!enabled || (right == SwipeAct.off && left == SwipeAct.off)) return child;
    return _SwipeRow(
      right: right == SwipeAct.off ? null : () => _look(right, scheme),
      left: left == SwipeAct.off ? null : () => _look(left, scheme),
      onRight: () => _run(right),
      onLeft: () => _run(left),
      backdrop: backdrop ?? Scaffold.maybeOf(context)?.widget.backgroundColor ?? scheme.surface,
      child: child,
    );
  }
}

/// 可左右滑的一行（Mihon、Gmail 那样）：
/// - 拖开时底下先是中性灰，图标跟着拖动距离慢慢变大；过了触发线背景一下子换成动作的颜色、图标弹一下、轻震一次，退回线内又变回灰
/// - 过了触发线再往外拖越来越"沉"（橡皮筋），不会把整行拖出屏幕
/// - 松手：过线就执行，行用弹簧回到原位；回去的路上底下一直显示拖开时的样子，不会因为状态已经变了闪成另一个动作
class _SwipeRow extends StatefulWidget {
  const _SwipeRow({required this.right, required this.left, required this.onRight, required this.onLeft, required this.backdrop, required this.child});

  /// 右滑 / 左滑的样子（图标、文字、颜色）；null 表示这个方向不能滑
  final (IconData, String, Color) Function()? right;
  final (IconData, String, Color) Function()? left;
  final Future<void> Function() onRight;
  final Future<void> Function() onLeft;
  final Color backdrop;
  final Widget child;

  @override
  State<_SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<_SwipeRow> with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this)..addStatusListener(_onStatus);
  double _raw = 0; // 手指实际拖了多远，显示的位置是它过一道橡皮筋
  double _width = 1;
  bool _armed = false;
  (IconData, String, Color)? _look; // 拖开时定下的样子，回到原位前不变
  bool _toRight = true;

  double get _trigger => _width * 0.25;

  void _onStatus(AnimationStatus _) {
    if (_offset.isAnimating || _offset.value.abs() >= 0.5) return;
    // 弹簧停下时离 0 还差一点点，对齐到 0（否则底色一直垫着）
    if (_offset.value != 0) _offset.value = 0;
    // 弹回原位后才放下定好的样子，下次拖开按最新状态取
    if (_look != null) setState(() => _look = null);
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  /// 过了触发线以后每多拖 1 像素只走 0.3 像素，最多走到半行宽
  double _rubber(double raw) {
    final a = raw.abs();
    if (a <= _trigger) return raw;
    final extra = math.min((a - _trigger) * 0.3, _width * 0.5 - _trigger);
    return raw.sign * (_trigger + extra);
  }

  void _start(DragStartDetails _) {
    _offset.stop();
    _raw = _offset.value;
  }

  void _update(DragUpdateDetails d) {
    var raw = _raw + d.primaryDelta!;
    if (widget.right == null) raw = math.min(raw, 0);
    if (widget.left == null) raw = math.max(raw, 0);
    _raw = raw;
    if (raw != 0 && (_look == null || (raw > 0) != _toRight)) {
      _toRight = raw > 0;
      _look = (_toRight ? widget.right : widget.left)!();
    }
    final x = _rubber(raw);
    final armed = x.abs() >= _trigger;
    if (armed != _armed) {
      HapticFeedback.selectionClick();
      setState(() => _armed = armed);
    }
    _offset.value = x;
  }

  void _end(double velocity) {
    final fire = _armed;
    final toRight = _toRight;
    _armed = false;
    _raw = 0;
    // 临界阻尼的弹簧：带着松手时的速度回去，不过冲（过冲会露出另一边）
    _offset.animateWith(SpringSimulation(SpringDescription.withDampingRatio(mass: 1, stiffness: 520, ratio: 1), _offset.value, 0, velocity * 0.3));
    setState(() {});
    if (fire) (toRight ? widget.onRight : widget.onLeft)(); // 执行完会自己轻震一下
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        _width = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.sizeOf(context).width;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _start,
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
          onHorizontalDragCancel: () => _end(0),
          child: AnimatedBuilder(
            animation: _offset,
            child: widget.child,
            builder: (context, child) {
              final x = _offset.value;
              final look = _look;
              return Stack(
                children: [
                  if (x != 0 && look != null) Positioned.fill(child: _background(look, x, scheme)),
                  Transform.translate(
                    offset: Offset(x, 0),
                    // 只在滑开时垫底色：平时透明，页面背景渐变时不会和它错开
                    child: ColoredBox(color: x != 0 ? widget.backdrop : Colors.transparent, child: child),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _background((IconData, String, Color) look, double x, ColorScheme scheme) {
    final (icon, label, color) = look;
    final progress = (x.abs() / _trigger).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: _armed ? 1 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      builder: (context, t, _) {
        final k = t.clamp(0.0, 1.0);
        final fg = Color.lerp(scheme.onSurfaceVariant, Colors.white, k)!;
        return ColoredBox(
          color: Color.lerp(scheme.surfaceContainerHighest, color, k)!,
          child: Align(
            alignment: _toRight ? Alignment.centerLeft : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Opacity(
                opacity: progress,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 拖动时从 0.6 慢慢长到 1，过线再弹到 1.15
                    Transform.scale(scale: 0.6 + 0.4 * progress + 0.15 * t, child: Icon(icon, color: fg)),
                    const SizedBox(width: 8),
                    Text(label, style: TextStyle(color: fg, fontWeight: k > 0.5 ? FontWeight.w600 : null)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
