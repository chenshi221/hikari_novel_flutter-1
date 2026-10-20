import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/cat_chapter.dart';
import '../../models/content.dart';
import '../data.dart';
import '../env.dart';
import '../pages/novel_page.dart';
import '../progress.dart';
import '../settings.dart';
import '../widgets.dart';
import 'paginator.dart';

/// 章节正文缓存在内存里，预加载下一章时也走这里。
final chapterProvider = FutureProvider.family<Content, (String, String)>((ref, key) => ref.watch(apiProvider).chapter(key.$1, key.$2));

class _Palette {
  const _Palette(this.bg, this.fg);

  final Color bg;
  final Color fg;
}

_Palette _paletteOf(ReaderPrefs prefs, ColorScheme scheme) => switch (prefs.theme) {
  0 => const _Palette(Color(0xFFF6F1E7), Color(0xFF2B2A27)),
  1 => const _Palette(Color(0xFFCFE6D0), Color(0xFF263A27)),
  2 => const _Palette(Color(0xFF1C1C1A), Color(0xFFBDBBB2)),
  _ => _Palette(scheme.surface, scheme.onSurface),
};

/// 阅读器。排版（paginator.dart）和界面分开：这里只管取章节、预加载、保存进度和操作栏。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.aid, required this.cid});

  final String aid;
  final String cid;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late String _cid = widget.cid;
  bool _bar = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _go(String cid) {
    if (cid == _cid) return;
    ReadingProgress.save(widget.aid, cid, 0);
    setState(() {
      _cid = cid;
      _bar = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(readerPrefsProvider);
    final palette = _paletteOf(prefs, Theme.of(context).colorScheme);
    final novel = ref.watch(novelProvider(widget.aid)).value;
    final chapters = novel?.catalogue.expand((v) => v.chapters).toList() ?? const <CatChapter>[];
    final index = chapters.indexWhere((c) => c.cid == _cid);
    final prev = index > 0 ? chapters[index - 1] : null;
    final next = index >= 0 && index < chapters.length - 1 ? chapters[index + 1] : null;
    final content = ref.watch(chapterProvider((widget.aid, _cid)));
    if (next != null) ref.listen(chapterProvider((widget.aid, _cid)), (_, s) => s.hasValue ? ref.read(chapterProvider((widget.aid, next.cid))) : null);

    final saved = ReadingProgress.of(widget.aid);
    final startOffset = saved?.cid == _cid ? saved!.offset : 0;
    void save(int offset) => ReadingProgress.save(widget.aid, _cid, offset);

    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          content.when(
            loading: () => Center(child: CircularProgressIndicator(color: palette.fg)),
            error: (e, _) => StatePanel(title: '章节加载失败', detail: e.toString(), onRetry: () => ref.invalidate(chapterProvider((widget.aid, _cid)))),
            data: (c) {
              final body = prefs.paged
                  ? _PagedBody(key: ValueKey((_cid, prefs.fontSize, prefs.lineHeight)), content: c, prefs: prefs, color: palette.fg, startOffset: startOffset, onOffset: save, onPrev: prev == null ? null : () => _go(prev.cid), onNext: next == null ? null : () => _go(next.cid), onToggleBar: () => setState(() => _bar = !_bar))
                  : _ScrollBody(key: ValueKey(_cid), content: c, prefs: prefs, color: palette.fg, startOffset: startOffset, onOffset: save, onNext: next == null ? null : () => _go(next.cid), onToggleBar: () => setState(() => _bar = !_bar));
              return body;
            },
          ),
          if (_bar) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 2,
                child: SafeArea(
                  bottom: false,
                  child: ListTile(
                    leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
                    title: Text(index >= 0 ? chapters[index].title : '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 2,
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      TextButton(onPressed: prev == null ? null : () => _go(prev.cid), child: const Text('上一章')),
                      TextButton(onPressed: () => _showCatalogue(chapters, index), child: const Text('目录')),
                      TextButton(onPressed: _showSettings, child: const Text('设置')),
                      TextButton(onPressed: next == null ? null : () => _go(next.cid), child: const Text('下一章')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showCatalogue(List<CatChapter> chapters, int current) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView.builder(
          controller: scroll,
          itemCount: chapters.length,
          itemBuilder: (context, i) => ListTile(
            dense: true,
            selected: i == current,
            title: Text(chapters[i].title),
            onTap: () {
              Navigator.pop(context);
              _go(chapters[i].cid);
            },
          ),
        ),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final prefs = ref.watch(readerPrefsProvider);
          void set(ReaderPrefs p) => ref.read(readerPrefsProvider.notifier).update(p);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('字号 ${prefs.fontSize.round()}'),
                  Slider(min: 14, max: 32, divisions: 18, value: prefs.fontSize, onChanged: (v) => set(prefs.copyWith(fontSize: v))),
                  Text('行距 ${prefs.lineHeight.toStringAsFixed(1)}'),
                  Slider(min: 1.3, max: 2.4, divisions: 11, value: prefs.lineHeight, onChanged: (v) => set(prefs.copyWith(lineHeight: v))),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (i, name) in ['纸张', '护眼', '夜间', '跟随应用'].indexed) ChoiceChip(label: Text(name), selected: prefs.theme == i, onSelected: (_) => set(prefs.copyWith(theme: i))),
                    ],
                  ),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('左右翻页'), value: prefs.paged, onChanged: (v) => set(prefs.copyWith(paged: v))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

TextStyle _style(ReaderPrefs prefs, Color color) => TextStyle(fontSize: prefs.fontSize, height: prefs.lineHeight, color: color);

class _ScrollBody extends StatefulWidget {
  const _ScrollBody({super.key, required this.content, required this.prefs, required this.color, required this.startOffset, required this.onOffset, required this.onNext, required this.onToggleBar});

  final Content content;
  final ReaderPrefs prefs;
  final Color color;
  final int startOffset;
  final ValueChanged<int> onOffset;
  final VoidCallback? onNext;
  final VoidCallback onToggleBar;

  @override
  State<_ScrollBody> createState() => _ScrollBodyState();
}

class _ScrollBodyState extends State<_ScrollBody> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients || widget.content.text.isEmpty) return;
      _controller.jumpTo((widget.startOffset / widget.content.text.length * _controller.position.maxScrollExtent).clamp(0, _controller.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.content;
    return NotificationListener<ScrollEndNotification>(
      onNotification: (n) {
        final max = n.metrics.maxScrollExtent;
        if (max > 0) widget.onOffset((n.metrics.pixels / max * c.text.length).round().clamp(0, c.text.length));
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggleBar,
        child: SingleChildScrollView(
          controller: _controller,
          padding: EdgeInsets.fromLTRB(22, MediaQuery.paddingOf(context).top + 24, 22, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(c.text, style: _style(widget.prefs, widget.color)),
              for (final url in c.images)
                Padding(padding: const EdgeInsets.only(top: 16), child: Image.network(displayImageUrl(url))),
              if (widget.onNext != null) Padding(padding: const EdgeInsets.only(top: 32), child: OutlinedButton(onPressed: widget.onNext, child: const Text('下一章'))),
            ],
          ),
        ),
      ),
    );
  }
}

class _PagedBody extends StatefulWidget {
  const _PagedBody({super.key, required this.content, required this.prefs, required this.color, required this.startOffset, required this.onOffset, required this.onPrev, required this.onNext, required this.onToggleBar});

  final Content content;
  final ReaderPrefs prefs;
  final Color color;
  final int startOffset;
  final ValueChanged<int> onOffset;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onToggleBar;

  @override
  State<_PagedBody> createState() => _PagedBodyState();
}

class _PagedBodyState extends State<_PagedBody> {
  PageController? _controller;
  List<int> _starts = const [0];

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _turn(int delta) {
    final c = _controller!;
    final target = (c.page ?? 0).round() + delta;
    final total = _starts.length + widget.content.images.length;
    if (target < 0) return widget.onPrev?.call();
    if (target >= total) return widget.onNext?.call();
    c.animateToPage(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.content;
    final padding = EdgeInsets.fromLTRB(22, MediaQuery.paddingOf(context).top + 20, 22, MediaQuery.paddingOf(context).bottom + 28);
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth - padding.horizontal, box.maxHeight - padding.vertical);
        final style = _style(widget.prefs, widget.color);
        _starts = paginate(c.text, style, size);
        _controller ??= PageController(initialPage: pageOfOffset(_starts, widget.startOffset));
        final total = _starts.length + c.images.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final x = d.localPosition.dx / box.maxWidth;
            if (x < 0.3) {
              _turn(-1);
            } else if (x > 0.7) {
              _turn(1);
            } else {
              widget.onToggleBar();
            }
          },
          child: PageView.builder(
            controller: _controller,
            itemCount: total,
            onPageChanged: (i) => widget.onOffset(i < _starts.length ? _starts[i] : c.text.length),
            itemBuilder: (context, i) {
              if (i >= _starts.length) return Center(child: Image.network(displayImageUrl(c.images[i - _starts.length])));
              final end = i + 1 < _starts.length ? _starts[i + 1] : c.text.length;
              return Padding(
                padding: padding,
                child: Stack(
                  children: [
                    Text(c.text.substring(_starts[i], end), style: style),
                    Positioned(right: 0, bottom: -22, child: Text('${i + 1}/$total', style: TextStyle(fontSize: 11, color: widget.color.withValues(alpha: 0.5)))),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
