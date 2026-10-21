import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/cat_chapter.dart';
import '../../models/cat_volume.dart';
import '../bookmarks.dart';
import '../cache.dart';
import '../data.dart';
import '../env.dart';
import '../fonts.dart';
import '../history.dart';
import '../pages/novel_page.dart';
import '../pages/rules_page.dart' show showRuleDialog;
import '../progress.dart';
import '../read_state.dart';
import '../rules.dart';
import '../settings.dart';
import '../stats.dart';
import '../widgets.dart';
import 'reader_body.dart';

/// 每个非空行当一段：去掉网页里零散的空白，统一首行缩进两个全角空格。
String formatChapter(String raw) => raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).map((l) => '　　$l').join('\n');

/// 章节：先查离线缓存，再联网；套用替换规则、统一缩进后算出高亮位置。
/// 读过的章节在内存里留 3 分钟（预加载的下一章、来回翻章都不用重新取），之后释放。
final chapterProvider = FutureProvider.autoDispose.family<Chapter, (String, String)>((ref, key) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 3), link.close);
  ref.onDispose(timer.cancel);
  final raw = await ChapterCache.get(key.$1, key.$2) ?? await ref.read(apiProvider).chapter(key.$1, key.$2);
  final text = formatChapter(ReplaceRules.apply(raw.text));
  return Chapter(text: text, images: raw.images, marks: ReplaceRules.marks(text));
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

/// 阅读器：这里只管取章节、预加载、进度、书签、朗读和菜单；排版在 paginator.dart，正文显示在 reader_body.dart，仿真翻页在 page_curl.dart。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.aid, required this.cid, this.offset});

  final String aid;
  final String cid;

  /// 从书签进来时的章内位置；不传就用保存的阅读进度
  final int? offset;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> with WidgetsBindingObserver {
  // ---- 阅读统计：只在界面可见时计时 ----
  final _watch = Stopwatch()..start();

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

  // ---- 当前章节与位置 ----
  late String _cid = widget.cid;
  bool _bar = false;
  int _epoch = 0; // 同一章内跳转（书签）时递增，让正文重新定位
  int _offset = 0; // 当前读到的字符偏移
  Object? _shown; // 正文第一次显示的标记 (cid, epoch)，用来在那一刻初始化 _offset
  int? _initial; // 从书签进来时的起点，只用一次
  String? _recorded;
  String? _selected;
  double? _slide;
  String? _bookTitle;
  String _chapterTitle = '';

  // ---- 朗读：按段落依次朗读，读完一章自动翻到下一章继续 ----
  final _tts = FlutterTts();
  bool _speaking = false;
  bool _resumeTts = false;
  List<String> _paras = const [];
  int _pi = 0;
  CatChapter? _nextChapter;

  @override
  void initState() {
    super.initState();
    _initial = widget.offset;
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

  /// 从当前阅读位置所在的段落开始读。
  Future<void> _startTts(Chapter c) async {
    final paras = <String>[];
    var startIndex = 0, pos = 0;
    for (final line in c.text.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) {
        if (pos <= _offset) startIndex = paras.length;
        paras.add(t);
      }
      pos += line.length + 1;
    }
    _paras = paras;
    _pi = _resumeTts ? 0 : startIndex;
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
    _go(next.cid, keepTts: true);
  }

  Future<void> _stopTts() async {
    _resumeTts = false;
    await _tts.stop();
    if (mounted) setState(() => _speaking = false);
  }

  void _toggleBar() {
    setState(() => _bar = !_bar);
    SystemChrome.setEnabledSystemUIMode(_bar ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  /// 跳到某章的某个位置。[offset] 默认章首；往前翻章时传 [kToEnd]，落在上一章的最后一页。
  /// 手动切章会停掉朗读（[keepTts] 是朗读自己读完一章后的自动续读）；往后翻时把离开的这章标为已读。
  void _go(String cid, {int offset = 0, bool keepTts = false}) {
    if (cid == _cid && offset == 0) return;
    if (!keepTts && _speaking) _stopTts();
    final next = _nextChapter;
    if (next != null && cid == next.cid) _markRead();
    ReadingProgress.save(widget.aid, cid, offset);
    setState(() {
      if (cid != _cid) _offset = offset == kToEnd ? 0 : offset;
      _cid = cid;
      _initial = null;
      _shown = null;
      _epoch++;
      _bar = false;
    });
  }

  void _markRead() {
    final len = ref.read(chapterProvider((widget.aid, _cid))).value?.text.length ?? 0;
    ReadState.mark(widget.aid, _cid, len);
  }

  void _saveOffset(int offset) {
    _offset = offset;
    ReadingProgress.save(widget.aid, _cid, offset);
  }

  // ---- 书签 ----
  Future<void> _addBookmark({String? selection}) async {
    final text = ref.read(chapterProvider((widget.aid, _cid))).value?.text ?? '';
    var at = _offset.clamp(0, text.length);
    String excerpt;
    if (selection != null && selection.trim().isNotEmpty) {
      // 选中文字：书签落在选中的那一处（从当前页开头往后找，找不到再退回当前位置）
      final idx = text.indexOf(selection.trim(), (at - 200).clamp(0, text.length));
      if (idx >= 0) at = idx;
      excerpt = selection.trim();
      if (excerpt.length > 40) excerpt = excerpt.substring(0, 40);
    } else {
      excerpt = text.substring(at, (at + 40).clamp(0, text.length)).replaceAll(RegExp(r'[\s　]+'), ' ').trim();
    }
    final added = await Bookmarks.toggle(widget.aid, _bookTitle ?? '', _cid, _chapterTitle, at, excerpt);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? '已加书签' : '已取消书签'), duration: const Duration(seconds: 1)));
    }
  }

  // ---- 选字菜单与高亮备注 ----
  bool get _hasSelection => (_selected ?? '').isNotEmpty;

  /// 选中的文字变成正则：空白（含缩进、换行）都换成 `\s*`，这样跨段选中也能匹配原文。
  static String _patternOf(String selected) => selected.split(RegExp(r'[\s　]+')).where((e) => e.isNotEmpty).map(RegExp.escape).join(r'\s*');

  Widget _selectionMenu(BuildContext context, SelectableRegionState state) => AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: [
      ...state.contextMenuButtonItems,
      ContextMenuButtonItem(label: '替换/屏蔽', onPressed: () => _ruleFromSelection(state, RuleKind.replace)),
      ContextMenuButtonItem(label: '高亮', onPressed: () => _ruleFromSelection(state, RuleKind.highlight)),
      ContextMenuButtonItem(
        label: '加书签',
        onPressed: () {
          final text = _selected ?? '';
          state.hideToolbar();
          _addBookmark(selection: text);
        },
      ),
    ],
  );

  Future<void> _ruleFromSelection(SelectableRegionState state, RuleKind kind) async {
    final text = (_selected ?? '').trim();
    state.hideToolbar();
    if (text.isEmpty) return;
    final rule = await showRuleDialog(context, initial: ReplaceRule(pattern: _patternOf(text), replacement: '', kind: kind, name: kind == RuleKind.highlight && text.length <= 8 ? text : ''));
    if (rule == null) return;
    await ReplaceRules.save([...ReplaceRules.all(), rule]);
    ref.invalidate(chapterProvider);
  }

  Widget _selectable(Widget child) => SelectionArea(onSelectionChanged: (c) => _selected = c?.plainText, contextMenuBuilder: _selectionMenu, child: child);

  Future<void> _editNote(Mark m) async {
    final controller = TextEditingController(text: RuleNotes.get(widget.aid, m.rule.id));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(m.rule.color), shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text(m.rule.label))]),
        content: TextField(controller: controller, autofocus: true, minLines: 3, maxLines: 8, decoration: const InputDecoration(hintText: '写点备注：身份、关系、伏笔……')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
        ],
      ),
    );
    if (saved == true) {
      await RuleNotes.set(widget.aid, m.rule.id, controller.text);
      if (mounted) setState(() {});
    }
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
    // 章节一加载好就预加载下一章（用 read 触发，且每章只触发一次）
    if (next != null && content.hasValue && _preloaded != next.cid) {
      _preloaded = next.cid;
      Future.microtask(() {
        if (mounted) ref.read(chapterProvider((widget.aid, next.cid)));
      });
    }

    final title = index >= 0 ? chapters[index].title : '';
    _bookTitle = novel?.detail.title;
    _chapterTitle = title;
    final f = FontStore.resolve(prefs.font);
    final style = readerStyle(prefs, palette.fg, family: f.family, fallback: f.fallback);
    final noted = RuleNotes.of(widget.aid).keys.toSet();

    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          content.when(
            loading: () => Center(child: CircularProgressIndicator(color: palette.fg)),
            error: (e, _) => StatePanel(title: '章节加载失败', detail: e.toString(), error: e, onRetry: () => ref.invalidate(chapterProvider((widget.aid, _cid)))),
            data: (c) {
              if (_shown != (_cid, _epoch)) {
                // 这一章第一次显示：起点取书签 / 保存的进度，之后 _offset 随翻页更新
                _shown = (_cid, _epoch);
                final saved = ReadingProgress.of(widget.aid);
                _offset = _initial ?? (saved?.cid == _cid ? saved!.offset : _offset);
              }
              if (_recorded != _cid && novel != null) {
                _recorded = _cid;
                scheduleMicrotask(() {
                  ReadingHistory.record(widget.aid, novel.detail.title, novel.detail.imgUrl, _cid, title);
                  ReadingStats.addChapter(widget.aid, _cid);
                  ReadingStats.setMeta(widget.aid, novel.detail.title, novel.detail.author, novel.detail.imgUrl);
                });
              }
              if (_resumeTts) {
                scheduleMicrotask(() => _startTts(c));
              }
              InlineSpan spanOf(int from, int to) => buildSpan(c, from, to, style, noted);
              final key = ValueKey((_cid, _epoch, prefs.mode, prefs.font, prefs.fontSize, prefs.lineHeight, prefs.margin, c.marks.length, c.text.length));
              void onMark(Mark m) => _editNote(m);
              return prefs.mode == 0
                  ? ScrollBody(
                      key: key,
                      chapter: c,
                      spanOf: spanOf,
                      style: style,
                      margin: prefs.margin,
                      startOffset: _offset,
                      onOffset: _saveOffset,
                      onEnd: _markRead,
                      onNext: next == null ? null : () => _go(next.cid),
                      wrap: _selectable,
                      onTapZone: _toggleBar,
                      onMark: onMark,
                      hasSelection: () => _hasSelection,
                    )
                  : PagedBody(
                      key: key,
                      chapter: c,
                      spanOf: spanOf,
                      style: style,
                      margin: prefs.margin,
                      title: title,
                      curl: prefs.mode == 2,
                      background: palette.bg,
                      color: palette.fg,
                      startOffset: _offset,
                      onOffset: _saveOffset,
                      onEnd: _markRead,
                      onPrev: prev == null ? null : () => _go(prev.cid, offset: kToEnd),
                      onNext: next == null ? null : () => _go(next.cid),
                      wrap: _selectable,
                      onTapZone: _toggleBar,
                      onMark: onMark,
                      hasSelection: () => _hasSelection,
                    );
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
                    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (chapters.length > 1)
                        Row(
                          children: [
                            const SizedBox(width: 16),
                            Text('${index + 1}/${chapters.length}', style: Theme.of(context).textTheme.bodySmall),
                            Expanded(
                              child: Slider(
                                min: 0,
                                max: (chapters.length - 1).toDouble(),
                                divisions: chapters.length - 1,
                                value: (_slide ?? index).clamp(0, chapters.length - 1).toDouble(),
                                onChanged: (v) => setState(() => _slide = v),
                                onChangeEnd: (v) {
                                  _slide = null;
                                  _go(chapters[v.round()].cid);
                                },
                              ),
                            ),
                          ],
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          TextButton(onPressed: prev == null ? null : () => _go(prev.cid), child: const Text('上一章')),
                          TextButton(onPressed: () => _showCatalogue(novel?.catalogue ?? const [], _cid), child: const Text('目录')),
                          IconButton(tooltip: '书签', icon: Icon(Bookmarks.has(widget.aid, _cid, _offset) ? Icons.bookmark : Icons.bookmark_border), onPressed: _addBookmark),
                          TextButton(
                            onPressed: () {
                              if (_speaking) {
                                _stopTts();
                              } else {
                                content.whenData(_startTts);
                              }
                            },
                            child: Text(_speaking ? '停止' : '朗读'),
                          ),
                          TextButton(onPressed: _showSettings, child: const Text('设置')),
                          TextButton(onPressed: next == null ? null : () => _go(next.cid), child: const Text('下一章')),
                        ],
                      ),
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

  String? _preloaded;

  /// 目录（按卷分层，当前章所在的卷默认展开）、本书的书签、人物备注。
  void _showCatalogue(List<CatVolume> volumes, String current) {
    final theme = Theme.of(context);
    final read = ReadState.read(widget.aid);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DefaultTabController(
        length: 3,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (context, scroll) => Column(
            children: [
              const TabBar(tabs: [Tab(text: '目录'), Tab(text: '书签'), Tab(text: '备注')]),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      controller: scroll,
                      children: [
                        for (final v in volumes)
                          ExpansionTile(
                            initiallyExpanded: volumes.length == 1 || v.chapters.any((c) => c.cid == current),
                            title: Text(v.title, style: theme.textTheme.titleSmall),
                            subtitle: Text('${v.chapters.where((c) => read.contains(c.cid)).length}/${v.chapters.length} 章已读', style: theme.textTheme.bodySmall),
                            children: [
                              for (final c in v.chapters)
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.only(left: 32, right: 16),
                                  selected: c.cid == current,
                                  leading: read.contains(c.cid) ? const Icon(Icons.check, size: 16) : null,
                                  title: Text(c.title, style: read.contains(c.cid) && c.cid != current ? TextStyle(color: theme.colorScheme.onSurfaceVariant) : null),
                                  trailing: ChapterCache.has(widget.aid, c.cid) ? const Icon(Icons.download_done, size: 16) : null,
                                  onTap: () {
                                    Navigator.pop(context);
                                    _go(c.cid);
                                  },
                                ),
                            ],
                          ),
                      ],
                    ),
                    Builder(
                      builder: (context) {
                        final marks = Bookmarks.all(widget.aid);
                        return marks.isEmpty
                            ? const Center(child: Text('还没有书签'))
                            : ListView(
                                children: [
                                  for (final b in marks)
                                    ListTile(
                                      title: Text(b.excerpt.isEmpty ? b.chapter : b.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis),
                                      subtitle: Text(b.chapter, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _go(b.cid, offset: b.offset == 0 ? 1 : b.offset);
                                      },
                                    ),
                                ],
                              );
                      },
                    ),
                    Builder(
                      builder: (context) {
                        final notes = RuleNotes.of(widget.aid);
                        final rules = ReplaceRules.all().where((r) => r.kind == RuleKind.highlight && notes.containsKey(r.id)).toList();
                        return rules.isEmpty
                            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('还没有备注。\n给人物名设置"高亮"规则后，阅读时点一下它就能写备注。', textAlign: TextAlign.center)))
                            : ListView(
                                children: [
                                  for (final r in rules)
                                    ListTile(
                                      leading: CircleAvatar(radius: 8, backgroundColor: Color(r.color)),
                                      title: Text(r.label),
                                      subtitle: Text(notes[r.id]!, maxLines: 3, overflow: TextOverflow.ellipsis),
                                    ),
                                ],
                              );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final prefs = ref.watch(readerPrefsProvider);
          void set(ReaderPrefs p) => ref.read(readerPrefsProvider.notifier).update(p);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('字号 ${prefs.fontSize.round()}'),
                  Slider(min: 14, max: 32, divisions: 18, value: prefs.fontSize, onChanged: (v) => set(prefs.copyWith(fontSize: v))),
                  Text('行距 ${prefs.lineHeight.toStringAsFixed(1)}'),
                  Slider(min: 1.3, max: 2.4, divisions: 11, value: prefs.lineHeight, onChanged: (v) => set(prefs.copyWith(lineHeight: v))),
                  Text('页边距 ${prefs.margin.round()}'),
                  Slider(min: 8, max: 48, divisions: 20, value: prefs.margin, onChanged: (v) => set(prefs.copyWith(margin: v))),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in FontStore.names.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: prefs.font == e.key,
                          onSelected: (_) async {
                            if (e.key == 2 && FontStore.customFamily == null && !await FontStore.pick()) return;
                            set(prefs.copyWith(font: e.key));
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
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
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
