import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../rules.dart';
import '../settings.dart';
import '../widgets.dart';
import 'page_curl.dart';
import 'paginator.dart';

/// 章节：正文（已套用替换规则、统一缩进）、插图地址、高亮位置。
class Chapter {
  const Chapter({required this.text, required this.images, required this.marks});

  final String text;
  final List<String> images;
  final List<Mark> marks;
}

/// 往前翻章时用的"落在最后一页"标记（偏移量超出任何正文）。
const kToEnd = 1 << 30;

typedef SpanOf = InlineSpan Function(int from, int to);

/// 阅读正文样式。分页测量和实际显示必须用**完全相同**的样式，所以把会被主题继承的属性都写死。
TextStyle readerStyle(ReaderPrefs prefs, Color color, {String? family, List<String>? fallback}) => TextStyle(
  fontSize: prefs.fontSize,
  height: prefs.lineHeight,
  color: color,
  fontFamily: family,
  fontFamilyFallback: fallback,
  fontWeight: FontWeight.w400,
  fontStyle: FontStyle.normal,
  letterSpacing: 0,
  wordSpacing: 0,
  decoration: TextDecoration.none,
  leadingDistribution: TextLeadingDistribution.proportional,
);

/// 取出 [from, to) 这一段正文，高亮的地方染色（有备注的加虚线下划线）。颜色和下划线不改变字形宽度，不影响分页。
InlineSpan buildSpan(Chapter c, int from, int to, TextStyle base, Set<String> noted) {
  final children = <InlineSpan>[];
  var pos = from;
  for (final m in c.marks) {
    if (m.end <= from) continue;
    if (m.start >= to) break;
    final s = math.max(m.start, from), e = math.min(m.end, to);
    if (s > pos) children.add(TextSpan(text: c.text.substring(pos, s)));
    final color = Color(m.rule.color);
    children.add(
      TextSpan(
        text: c.text.substring(s, e),
        style: TextStyle(color: color, backgroundColor: color.withValues(alpha: 0.13), decoration: noted.contains(m.rule.id) ? TextDecoration.underline : null, decorationStyle: TextDecorationStyle.dotted, decorationColor: color),
      ),
    );
    pos = e;
  }
  if (pos < to) children.add(TextSpan(text: c.text.substring(pos, to)));
  return TextSpan(style: base, children: children);
}

/// 点击检测：用原始指针事件，不进手势竞技场，所以不会被 [SelectionArea] 或翻页手势吞掉。
/// 按下后移动不到 14 像素、300 毫秒内抬起算一次点击；按下时已有选中文字则这次点击只用来取消选择。
class TapDetector extends StatefulWidget {
  const TapDetector({super.key, required this.child, required this.onTap, this.hasSelection});

  final Widget child;

  /// [local] 是点击在本组件内的位置，[size] 是组件大小，[global] 是屏幕位置
  final void Function(Offset local, Size size, Offset global) onTap;
  final bool Function()? hasSelection;

  @override
  State<TapDetector> createState() => _TapDetectorState();
}

class _TapDetectorState extends State<TapDetector> {
  Offset? _down;
  DateTime _at = DateTime.now();
  bool _ignore = false;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (e) {
      _down = e.position;
      _at = DateTime.now();
      _ignore = widget.hasSelection?.call() ?? false;
    },
    onPointerMove: (e) {
      if (_down != null && (e.position - _down!).distance > 14) _down = null;
    },
    onPointerCancel: (_) => _down = null,
    onPointerUp: (e) {
      final d = _down;
      _down = null;
      if (d == null || _ignore || DateTime.now().difference(_at) > const Duration(milliseconds: 300)) return;
      final box = context.findRenderObject() as RenderBox;
      widget.onTap(box.globalToLocal(e.position), box.size, e.position);
    },
    child: widget.child,
  );
}

/// 在 [key] 对应的段落里找屏幕位置 [global] 点中了哪个高亮，[base] 是这段文字在整章里的起点。
Mark? markAt(Chapter c, GlobalKey key, int base, Offset global) {
  final ro = key.currentContext?.findRenderObject();
  if (ro is! RenderParagraph) return null;
  final local = ro.globalToLocal(global);
  final pos = ro.getPositionForOffset(local).offset;
  // 只认真正落在那个字上的点击，行尾空白处不算
  final boxes = ro.getBoxesForSelection(TextSelection(baseOffset: pos, extentOffset: pos + 1));
  if (!boxes.any((b) => b.toRect().inflate(2).contains(local))) return null;
  final idx = base + pos;
  for (final m in c.marks) {
    if (idx >= m.start && idx < m.end) return m;
  }
  return null;
}

/// 上下滚动。进度用字符偏移：保存时取视口顶部对应的字符，恢复时再换算回滚动位置，所以改字号、延迟加载插图都不会跳位置。
class ScrollBody extends StatefulWidget {
  const ScrollBody({
    super.key,
    required this.chapter,
    required this.spanOf,
    required this.style,
    required this.margin,
    required this.startOffset,
    required this.onOffset,
    required this.onEnd,
    required this.onNext,
    required this.wrap,
    required this.onTapZone,
    required this.onMark,
    required this.hasSelection,
  });

  final Chapter chapter;
  final SpanOf spanOf;
  final TextStyle style;
  final double margin;
  final int startOffset;
  final ValueChanged<int> onOffset;

  /// 滚到章末
  final VoidCallback onEnd;
  final VoidCallback? onNext;
  final Widget Function(Widget) wrap;

  /// 点在空白处（切换菜单栏）
  final VoidCallback onTapZone;
  final void Function(Mark) onMark;
  final bool Function() hasSelection;

  @override
  State<ScrollBody> createState() => _ScrollBodyState();
}

class _ScrollBodyState extends State<ScrollBody> {
  final _controller = ScrollController();
  final _textKey = GlobalKey();
  double _padTop = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _restore() {
    if (!mounted || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    final off = widget.startOffset;
    final ro = _textKey.currentContext?.findRenderObject();
    if (off >= kToEnd) return _controller.jumpTo(max);
    if (off <= 0 || ro is! RenderParagraph) return;
    final caret = ro.getOffsetForCaret(TextPosition(offset: math.min(off, widget.chapter.text.length)), Rect.zero);
    _controller.jumpTo((_padTop + caret.dy).clamp(0.0, max));
  }

  int _charAtTop() {
    final ro = _textKey.currentContext?.findRenderObject();
    if (ro is! RenderParagraph) return 0;
    final top = (context.findRenderObject() as RenderBox).localToGlobal(Offset.zero).dy;
    final y = top - ro.localToGlobal(Offset.zero).dy;
    return y <= 0 ? 0 : ro.getPositionForOffset(Offset(0, y)).offset;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.chapter;
    _padTop = MediaQuery.viewPaddingOf(context).top + 24;
    return NotificationListener<ScrollEndNotification>(
      onNotification: (n) {
        widget.onOffset(_charAtTop());
        if (n.metrics.maxScrollExtent <= 0 || n.metrics.pixels >= n.metrics.maxScrollExtent - 40) widget.onEnd();
        return false;
      },
      child: TapDetector(
        hasSelection: widget.hasSelection,
        onTap: (local, size, global) {
          final m = markAt(c, _textKey, 0, global);
          m != null ? widget.onMark(m) : widget.onTapZone();
        },
        child: widget.wrap(
          SingleChildScrollView(
            controller: _controller,
            padding: EdgeInsets.fromLTRB(widget.margin, _padTop, widget.margin, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(widget.spanOf(0, c.text.length), key: _textKey, textScaler: TextScaler.noScaling),
                for (final url in c.images) Padding(padding: const EdgeInsets.only(top: 16), child: NetImage(url, fit: BoxFit.contain)),
                if (widget.onNext != null) Padding(padding: const EdgeInsets.only(top: 32), child: OutlinedButton(onPressed: widget.onNext, child: const Text('下一章'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 左右翻页（滑动 / 仿真）。页面大小或字号、字体变了会重新分页，并按"当前读到的字符"回到同一处。
class PagedBody extends StatefulWidget {
  const PagedBody({
    super.key,
    required this.chapter,
    required this.spanOf,
    required this.style,
    required this.margin,
    required this.title,
    required this.curl,
    required this.background,
    required this.color,
    required this.startOffset,
    required this.onOffset,
    required this.onEnd,
    required this.onPrev,
    required this.onNext,
    required this.wrap,
    required this.onTapZone,
    required this.onMark,
    required this.hasSelection,
  });

  final Chapter chapter;
  final SpanOf spanOf;
  final TextStyle style;
  final double margin;
  final String title;
  final bool curl;
  final Color background;
  final Color color;
  final int startOffset;
  final ValueChanged<int> onOffset;
  final VoidCallback onEnd;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final Widget Function(Widget) wrap;
  final VoidCallback onTapZone;
  final void Function(Mark) onMark;
  final bool Function() hasSelection;

  @override
  State<PagedBody> createState() => _PagedBodyState();
}

class _PagedBodyState extends State<PagedBody> {
  final _curl = PageCurlController();
  final _keys = <int, GlobalKey>{};
  PageController? _controller;
  List<int> _starts = const [0];
  Object? _sig;
  int _page = 0;
  int _cur = 0; // 当前读到的字符偏移，重新分页时按它定位
  double _overscroll = 0;

  @override
  void initState() {
    super.initState();
    _cur = widget.startOffset;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Chapter get _c => widget.chapter;

  bool get _hasText => _c.text.trim().isNotEmpty;

  int get _textPages => _hasText ? _starts.length : 0;

  int get _total => _textPages + _c.images.length;

  int _offsetOf(int page) => page < _textPages ? _starts[page] : _c.text.length + 1 + (page - _textPages);

  int _pageOf(int offset) {
    if (_total == 0) return 0;
    if (offset >= kToEnd) return _total - 1;
    if (offset > _c.text.length) return math.min(_textPages + (offset - _c.text.length - 1), _total - 1);
    return _hasText ? pageOfOffset(_starts, offset) : 0;
  }

  GlobalKey _keyFor(int page) => _keys.putIfAbsent(page, GlobalKey.new);

  void _changed(int page) {
    _page = page;
    _cur = _offsetOf(page);
    widget.onOffset(_cur);
    if (page >= _total - 1) widget.onEnd();
  }

  Widget _pageContent(BuildContext context, int i, bool live, EdgeInsets pad) {
    if (i >= _textPages) return Center(child: NetImage(_c.images[i - _textPages], fit: BoxFit.contain));
    final end = i + 1 < _starts.length ? _starts[i + 1] : _c.text.length;
    final faint = TextStyle(fontSize: 11, color: widget.color.withValues(alpha: 0.5));
    final view = MediaQuery.viewPaddingOf(context);
    return Stack(
      children: [
        Padding(padding: pad, child: Text.rich(widget.spanOf(_starts[i], end), key: live ? _keyFor(i) : null, textScaler: TextScaler.noScaling)),
        Positioned(top: view.top + 10, left: widget.margin, right: widget.margin, child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: faint)),
        Positioned(bottom: view.bottom + 10, right: widget.margin, child: Text('${i + 1}/$_total', style: faint)),
      ],
    );
  }

  void _tap(Offset local, Size size, Offset global) {
    final m = _page < _textPages ? markAt(_c, _keyFor(_page), _starts[_page], global) : null;
    if (m != null) return widget.onMark(m);
    final x = local.dx / size.width;
    if (x < 0.3) {
      widget.curl ? _curl.prev() : _slide(-1);
    } else if (x > 0.7) {
      widget.curl ? _curl.next() : _slide(1);
    } else {
      widget.onTapZone();
    }
  }

  void _slide(int delta) {
    final target = _page + delta;
    if (target < 0) return widget.onPrev?.call();
    if (target >= _total) return widget.onNext?.call();
    _controller?.animateToPage(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.viewPaddingOf(context);
    final pad = EdgeInsets.fromLTRB(widget.margin, view.top + 36, widget.margin, view.bottom + 36);
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth - pad.horizontal, box.maxHeight - pad.vertical);
        // 同样的版面（大小、样式、正文）不重复分页；开关菜单栏、拖滑块这类重建不会触发全文排版
        final sig = Object.hash(size, widget.style, _c.text.length, _c.text.hashCode);
        if (sig != _sig) {
          final keep = _sig == null ? widget.startOffset : _cur;
          _sig = sig;
          _starts = _hasText ? paginate(_c.text, widget.style, size) : const [0];
          _controller?.dispose();
          _controller = null;
          _page = _pageOf(keep);
          _cur = _offsetOf(_page);
          _keys.clear();
        }
        final Widget pages;
        if (widget.curl) {
          pages = PageCurl(
            key: ValueKey(sig),
            controller: _curl,
            pageCount: _total,
            initialIndex: _page,
            background: widget.background,
            pageBuilder: (context, i, live) => _pageContent(context, i, live, pad),
            onIndexChanged: _changed,
            onReachStart: widget.onPrev,
            onReachEnd: widget.onNext,
          );
        } else {
          _controller ??= PageController(initialPage: _page);
          pages = NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // 第一页往前滑、最后一页往后滑：松手后切到上一章 / 下一章
              if (n is OverscrollNotification) _overscroll = n.overscroll;
              if (n is ScrollEndNotification) {
                if (_overscroll > 0) widget.onNext?.call();
                if (_overscroll < 0) widget.onPrev?.call();
                _overscroll = 0;
              }
              return false;
            },
            child: PageView.builder(
              key: ValueKey(sig),
              controller: _controller,
              physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
              itemCount: _total,
              onPageChanged: _changed,
              itemBuilder: (context, i) => _pageContent(context, i, true, pad),
            ),
          );
        }
        return TapDetector(hasSelection: widget.hasSelection, onTap: _tap, child: widget.wrap(pages));
      },
    );
  }
}
