import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/cat_chapter.dart';
import '../../models/cat_volume.dart';
import '../../models/content.dart';
import '../cache.dart';
import '../env.dart';
import '../fonts.dart';
import '../history.dart';
import '../rules.dart';
import '../stats.dart';
import '../data.dart';
import '../pages/novel_page.dart';
import '../progress.dart';
import '../settings.dart';
import '../widgets.dart';
import 'paginator.dart';
import 'paper_curl_pager.dart';

/// 章节正文缓存在内存里，预加载下一章时也走这里。
/// 每个非空行当一段：去掉网页里零散的空白，统一首行缩进两个全角空格。
String formatChapter(String raw) => raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).map((l) => '　　$l').join('\n');

final chapterProvider = FutureProvider.family<Content, (String, String)>((ref, key) async {
  final c = ChapterCache.get(key.$1, key.$2) ?? await ref.watch(apiProvider).chapter(key.$1, key.$2);
  return Content(text: formatChapter(ReplaceRules.apply(c.text)), images: c.images);
});

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

class _ReaderPageState extends ConsumerState<ReaderPage> with WidgetsBindingObserver {
  // 阅读统计：只在界面可见时计时
  final _watch = Stopwatch()..start();
  String? _recorded;

  void _flushStats() {
    final seconds = _watch.elapsed.inSeconds;
    if (seconds <= 0) return;
    ReadingStats.addSeconds(widget.aid, seconds);
    final running = _watch.isRunning;
    _watch.reset();
    if (running) _watch.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _watch.start();
    } else {
      _flushStats();
      _watch.stop();
    }
  }

  late String _cid = widget.cid;
  bool _bar = false;

  // 朗读：按段落依次朗读，读完一章自动翻到下一章继续
  final _tts = FlutterTts();
  bool _speaking = false;
  bool _resumeTts = false;
  List<String> _paras = const [];
  int _pi = 0;
  CatChapter? _nextChapter;

  Future<void> _startTts(Content c) async {
    _paras = c.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    _pi = 0;
    if (_paras.isEmpty) return;
    setState(() => _speaking = true);
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(ref.read(readerPrefsProvider).ttsRate);
    await _speakNext();
  }

  Future<void> _speakNext() async {
    if (!_speaking) return;
    if (_pi < _paras.length) {
      await _tts.speak(_paras[_pi]);
      return;
    }
    final next = _nextChapter;
    if (next == null) {
      await _stopTts();
      return;
    }
    _resumeTts = true;
    _go(next.cid);
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    if (mounted) setState(() => _speaking = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _tts.setCompletionHandler(() {
      _pi++;
      _speakNext();
    });
  }

  @override
  void dispose() {
    _tts.stop();
    WidgetsBinding.instance.removeObserver(this);
    _flushStats();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleBar() {
    setState(() => _bar = !_bar);
    SystemChrome.setEnabledSystemUIMode(_bar ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
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
    _nextChapter = next;
    final content = ref.watch(chapterProvider((widget.aid, _cid)));
    if (next != null) ref.listen(chapterProvider((widget.aid, _cid)), (_, s) => s.hasValue ? ref.read(chapterProvider((widget.aid, next.cid))) : null);

    final title = index >= 0 ? chapters[index].title : '';
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
              if (_recorded != _cid && novel != null) {
                _recorded = _cid;
                scheduleMicrotask(() {
                  ReadingHistory.record(widget.aid, novel.detail.title, novel.detail.imgUrl, _cid, title);
                  ReadingStats.addChapter(widget.aid, _cid);
                });
              }
              if (_resumeTts) {
                _resumeTts = false;
                scheduleMicrotask(() => _startTts(c));
              }
              final body = prefs.mode != 0
                  ? _PagedBody(key: ValueKey((_cid, prefs.fontSize, prefs.lineHeight, prefs.mode, prefs.margin)), title: title, curl: prefs.mode == 2, content: c, prefs: prefs, color: palette.fg, startOffset: startOffset, onOffset: save, onPrev: prev == null ? null : () => _go(prev.cid), onNext: next == null ? null : () => _go(next.cid), onToggleBar: _toggleBar)
                  : _ScrollBody(key: ValueKey(_cid), content: c, prefs: prefs, color: palette.fg, startOffset: startOffset, onOffset: save, onNext: next == null ? null : () => _go(next.cid), onToggleBar: _toggleBar);
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
                      TextButton(onPressed: () => _showCatalogue(novel?.catalogue ?? const [], _cid), child: const Text('目录')),
                      TextButton(
                        onPressed: () {
                          if (_speaking) {
                            _stopTts();
                          } else {
                            content.whenData(_startTts);
                          }
                        },
                        child: Text(_speaking ? '停止朗读' : '朗读'),
                      ),
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

  /// 目录按卷分层，当前章所在的卷默认展开。
  void _showCatalogue(List<CatVolume> volumes, String current) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            for (final v in volumes)
              ExpansionTile(
                initiallyExpanded: volumes.length == 1 || v.chapters.any((c) => c.cid == current),
                title: Text(v.title, style: theme.textTheme.titleSmall),
                subtitle: Text('${v.chapters.length} 章', style: theme.textTheme.bodySmall),
                children: [
                  for (final c in v.chapters)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 32, right: 16),
                      selected: c.cid == current,
                      leading: ChapterCache.has(widget.aid, c.cid) ? const Icon(Icons.download_done, size: 16) : null,
                      title: Text(c.title),
                      onTap: () {
                        Navigator.pop(context);
                        _go(c.cid);
                      },
                    ),
                ],
              ),
          ],
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
                      for (final (i, name) in ['默认字体', '衬线', '自选字体'].indexed)
                        ChoiceChip(
                          label: Text(name),
                          selected: prefs.font == i,
                          onSelected: (_) async {
                            if (i == 2 && FontStore.customFamily == null && !await FontStore.pick()) return;
                            set(prefs.copyWith(font: i));
                          },
                        ),
                      if (!isWebPreview)
                        ActionChip(
                          label: const Text('选择字体文件…'),
                          onPressed: () async {
                            if (await FontStore.pick()) set(prefs.copyWith(font: 2));
                          },
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (i, name) in ['纸张', '护眼', '夜间', '跟随应用'].indexed) ChoiceChip(label: Text(name), selected: prefs.theme == i, onSelected: (_) => set(prefs.copyWith(theme: i))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [ButtonSegment(value: 0, label: Text('滚动')), ButtonSegment(value: 1, label: Text('滑动')), ButtonSegment(value: 2, label: Text('仿真'))],
                    selected: {prefs.mode},
                    onSelectionChanged: (s) => set(prefs.copyWith(mode: s.first)),
                  ),
                  Text('页边距 ${prefs.margin.round()}'),
                  Slider(min: 8, max: 48, divisions: 20, value: prefs.margin, onChanged: (v) => set(prefs.copyWith(margin: v))),
                  Text('朗读语速 ${prefs.ttsRate.toStringAsFixed(1)}'),
                  Slider(min: 0.1, max: 1.0, divisions: 9, value: prefs.ttsRate, onChanged: (v) => set(prefs.copyWith(ttsRate: v))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

TextStyle _style(ReaderPrefs prefs, Color color) {
  final f = FontStore.resolve(prefs.font);
  return TextStyle(fontSize: prefs.fontSize, height: prefs.lineHeight, color: color, fontFamily: f.family, fontFamilyFallback: f.fallback);
}

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
          padding: EdgeInsets.fromLTRB(widget.prefs.margin, MediaQuery.paddingOf(context).top + 24, widget.prefs.margin, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(c.text, textScaler: TextScaler.noScaling, style: _style(widget.prefs, widget.color)),
              for (final url in c.images)
                Padding(padding: const EdgeInsets.only(top: 16), child: NetImage(url, fit: BoxFit.contain)),
              if (widget.onNext != null) Padding(padding: const EdgeInsets.only(top: 32), child: OutlinedButton(onPressed: widget.onNext, child: const Text('下一章'))),
            ],
          ),
        ),
      ),
    );
  }
}

class _PagedBody extends StatefulWidget {
  final String title;
  final bool curl;

  const _PagedBody({super.key, required this.title, required this.curl, required this.content, required this.prefs, required this.color, required this.startOffset, required this.onOffset, required this.onPrev, required this.onNext, required this.onToggleBar});

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
  double _overscroll = 0;

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
    final padding = EdgeInsets.fromLTRB(widget.prefs.margin, MediaQuery.paddingOf(context).top + 36, widget.prefs.margin, MediaQuery.paddingOf(context).bottom + 36);
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth - padding.horizontal, box.maxHeight - padding.vertical);
        final style = _style(widget.prefs, widget.color);
        _starts = paginate(c.text, style, size);
        _controller ??= PageController(initialPage: pageOfOffset(_starts, widget.startOffset));
        final total = _starts.length + c.images.length;
        Widget pageAt(int i) {
          if (i >= _starts.length) return Center(child: NetImage(c.images[i - _starts.length], fit: BoxFit.contain));
          final end = i + 1 < _starts.length ? _starts[i + 1] : c.text.length;
          final faint = TextStyle(fontSize: 11, color: widget.color.withValues(alpha: 0.5));
          return Stack(
            children: [
              Padding(padding: padding, child: Text(c.text.substring(_starts[i], end), textScaler: TextScaler.noScaling, style: style)),
              Positioned(top: MediaQuery.paddingOf(context).top + 10, left: widget.prefs.margin, right: widget.prefs.margin, child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: faint)),
              Positioned(bottom: MediaQuery.paddingOf(context).bottom + 10, right: widget.prefs.margin, child: Text('${i + 1}/$total', style: faint)),
            ],
          );
        }

        int offsetOf(int i) => i < _starts.length ? _starts[i] : c.text.length;
        if (widget.curl) {
          final bg = Theme.of(context).scaffoldBackgroundColor;
          return PaperCurlPager.builder(
            pageCount: total,
            initialIndex: pageOfOffset(_starts, widget.startOffset),
            backgroundColor: bg,
            pageBuilder: (_, i) => ColoredBox(color: bg, child: pageAt(i)),
            onIndexChanged: (i) => widget.onOffset(offsetOf(i)),
            onCenterTap: widget.onToggleBar,
            onReachStart: widget.onPrev,
            onReachEnd: widget.onNext,
          );
        }
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
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // 在第一页往前滑、最后一页往后滑，松手后切到上一章 / 下一章
              if (n is OverscrollNotification) _overscroll = n.overscroll;
              if (n is ScrollEndNotification) {
                if (_overscroll > 0) widget.onNext?.call();
                if (_overscroll < 0) widget.onPrev?.call();
                _overscroll = 0;
              }
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: total,
              onPageChanged: (i) => widget.onOffset(offsetOf(i)),
              itemBuilder: (context, i) => pageAt(i),
            ),
          ),
        );
      },
    );
  }
}
