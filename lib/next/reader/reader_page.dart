import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
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
import 'paginator.dart';
import 'reader_body.dart';

/// 每个非空行当一段：去掉网页里零散的空白，统一首行缩进两个全角空格。
String formatChapter(String raw) => raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).map((l) => '　　$l').join('\n');

/// 章节：先查离线缓存，再联网；套用替换规则、统一缩进后算出高亮位置。
/// 读过的章节在内存里留 3 分钟（预加载的下一章、来回翻章都不用重新取），之后释放。
final chapterProvider = FutureProvider.autoDispose.family<Chapter, (String, String)>((ref, key) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 3), link.close);
  ref.onDispose(timer.cancel);
  var raw = await ChapterCache.get(key.$1, key.$2);
  if (raw == null) {
    raw = await ref.read(apiProvider).chapter(key.$1, key.$2);
    // 读过的章节顺手存下来，断网也能再看；写失败不影响阅读
    try {
      await ChapterCache.put(key.$1, key.$2, raw);
    } catch (_) {}
  }
  final text = formatChapter(ReplaceRules.apply(raw.text));
  return Chapter(text: text, images: raw.images, marks: ReplaceRules.marks(text, null, key.$1));
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

  bool _background = false;

  /// 朗读中退到后台 / 锁屏也算在读，计时不停；朗读停下时若还在后台再停表。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state != AppLifecycleState.resumed;
    if (!_background) {
      _watch.start();
    } else if (!_speaking) {
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

  // ---- 朗读：按句依次朗读，高亮正在读的句子并跟着翻页，读完一章自动读下一章 ----
  final _tts = FlutterTts();
  bool _speaking = false;
  bool _resumeTts = false;
  List<(int, int)> _segs = const []; // 每句在章节正文里的 [start, end)
  String _ttsText = '';
  int _si = 0;
  DateTime _jumped = DateTime(0); // 手动跳句的时刻：刚被打断的那句的"读完"回调要忽略
  DateTime _spokeAt = DateTime(0); // 最近一句开始朗读的时刻：这之后马上发生的翻页是跟读造成的，不是用户翻的
  int _lastPageOffset = -1;
  Timer? _turnTimer;
  DateTime? _sleepAt; // 定时关闭
  bool _stopAtChapterEnd = false;
  CatChapter? _nextChapter;
  final _nav = ReaderNav();

  // ---- 页眉页脚的时间、电量：每分钟刷新一次，只重建页脚 ----
  final _status = ValueNotifier<String>('');
  final _pos = ValueNotifier<int>(0); // 滚动模式页脚用的当前字符偏移
  Timer? _clock;

  Future<void> _tick() async {
    final n = DateTime.now();
    var s = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    try {
      if (!isWebPreview) s += '  电量 ${await Battery().batteryLevel}%';
    } catch (_) {} // 没有电池的电脑 / 取不到就不显示电量
    if (mounted) _status.value = s;
  }

  @override
  void initState() {
    super.initState();
    _tick();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    _initial = widget.offset;
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _tts.setCompletionHandler(() {
      if (DateTime.now().difference(_jumped).inMilliseconds < 400) return;
      _si++;
      _speakNext();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _status.dispose();
    _pos.dispose();
    _turnTimer?.cancel();
    _tts.stop();
    WidgetsBinding.instance.removeObserver(this);
    _flushStats();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// 从当前阅读位置所在的句子开始读。
  Future<void> _startTts(Chapter c) async {
    _ttsText = c.text;
    _segs = splitSentences(c.text);
    if (_segs.isEmpty) return;
    final at = _resumeTts ? 0 : _offset;
    _si = _segs.indexWhere((e) => e.$2 > at);
    if (_si < 0) _si = _segs.length - 1;
    setState(() => _speaking = true);
    await _applyTtsPrefs();
    await _speakNext();
  }

  Future<void> _applyTtsPrefs() async {
    final prefs = ref.read(readerPrefsProvider);
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(prefs.ttsRate);
    await _tts.setPitch(prefs.ttsPitch);
    if (prefs.ttsVoice.isNotEmpty) {
      try {
        await _tts.setVoice({'name': prefs.ttsVoice, 'locale': 'zh-CN'});
      } catch (_) {}
    }
  }

  Future<void> _speakNext() async {
    if (!_speaking) return;
    if (_sleepAt != null && DateTime.now().isAfter(_sleepAt!)) return _stopTts();
    if (_si < _segs.length) {
      final (s, e) = _segs[_si];
      _spokeAt = DateTime.now();
      if (mounted) setState(() {});
      await _tts.speak(_ttsText.substring(s, e).trim());
      return;
    }
    final next = _nextChapter;
    if (next == null || _stopAtChapterEnd || !ref.read(readerPrefsProvider).ttsAutoNext) return _stopTts();
    _resumeTts = true;
    _go(next.cid, keepTts: true);
  }

  /// 上一句 / 下一句。
  void _skipSentence(int delta) {
    if (!_speaking) return;
    _si = (_si + delta).clamp(0, _segs.length - 1);
    _jumped = DateTime.now();
    _speakNext();
  }

  Future<void> _stopTts() async {
    _turnTimer?.cancel();
    if (_background) {
      _flushStats();
      _watch.stop();
    }
    _resumeTts = false;
    _sleepAt = null;
    _stopAtChapterEnd = false;
    await _tts.stop();
    if (mounted) setState(() => _speaking = false);
  }

  /// 键盘：→ ↓ 空格 PageDown 下一页，← ↑ Shift+空格 PageUp 上一页，] [ 下一章 / 上一章，Esc 呼出 / 收起菜单。
  KeyEventResult _onKey(KeyEvent e, CatChapter? prev, CatChapter? next, int mode) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final scroll = mode == 0;
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.pageDown || (key == LogicalKeyboardKey.space && !shift)) {
      _nav.next?.call();
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp || (key == LogicalKeyboardKey.space && shift)) {
      _nav.prev?.call();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      scroll ? _nav.scrollBy?.call(80) : _nav.next?.call();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      scroll ? _nav.scrollBy?.call(-80) : _nav.prev?.call();
    } else if (key == LogicalKeyboardKey.bracketRight && next != null) {
      _go(next.cid);
    } else if (key == LogicalKeyboardKey.bracketLeft && prev != null) {
      _go(prev.cid);
    } else if (key == LogicalKeyboardKey.escape) {
      _toggleBar();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
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
      _pos.value = _offset;
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
    _pos.value = offset;
    ReadingProgress.save(widget.aid, _cid, offset);
    // 朗读时用户自己翻页 / 滚动（不是跟读造成的）：停稳后从新位置的句子接着读
    final turned = offset != _lastPageOffset;
    _lastPageOffset = offset;
    if (_speaking && turned && DateTime.now().difference(_spokeAt).inMilliseconds > 1200) {
      _turnTimer?.cancel();
      _turnTimer = Timer(const Duration(milliseconds: 600), () => _readFrom(offset));
    }
  }

  void _readFrom(int offset) {
    if (!_speaking || !mounted || ref.read(chapterProvider((widget.aid, _cid))).value?.text != _ttsText) return;
    final i = _segs.indexWhere((e) => e.$2 > offset);
    if (i < 0 || i == _si) return;
    _si = i;
    _jumped = DateTime.now();
    _speakNext();
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

  /// 只保留我们需要的几项，不带系统自带的全选、分享、搜索、翻译。
  Widget _selectionMenu(BuildContext context, SelectableRegionState state) => AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: [
      ContextMenuButtonItem(
        label: '复制',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: _selected ?? ''));
          state.hideToolbar();
        },
      ),
      ContextMenuButtonItem(label: '替换/屏蔽', onPressed: () => _replaceFromSelection(state)),
      ContextMenuButtonItem(label: '高亮', onPressed: () => _highlightSelection(state)),
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

  Future<void> _replaceFromSelection(SelectableRegionState state) async {
    final text = (_selected ?? '').trim();
    state.hideToolbar();
    if (text.isEmpty) return;
    final rule = await showRuleDialog(context, initial: ReplaceRule(pattern: _patternOf(text), replacement: '', kind: RuleKind.replace));
    if (rule == null) return;
    await ReplaceRules.save([...ReplaceRules.all(), rule]);
    ref.invalidate(chapterProvider);
  }

  /// 高亮选中的文字：同一本书里相同的文字只有一条高亮规则，所有出现的地方共用一份备注。随后直接打开备注框。
  Future<void> _highlightSelection(SelectableRegionState state) async {
    final text = (_selected ?? '').trim();
    state.hideToolbar();
    if (text.isEmpty) return;
    final pattern = _patternOf(text);
    final rules = ReplaceRules.all();
    var rule = rules.where((r) => r.kind == RuleKind.highlight && r.pattern == pattern && (r.aid == widget.aid || r.aid.isEmpty)).firstOrNull;
    if (rule == null) {
      rule = ReplaceRule(pattern: pattern, replacement: '', kind: RuleKind.highlight, color: ruleColors[2], name: text.length <= 8 ? text : '', id: 'h${DateTime.now().microsecondsSinceEpoch}', aid: widget.aid);
      await ReplaceRules.save([...rules, rule]);
      ref.invalidate(chapterProvider);
    }
    if (mounted) await _editNote(rule);
  }

  Widget _selectable(Widget child) => SelectionArea(onSelectionChanged: (c) => _selected = c?.plainText, contextMenuBuilder: _selectionMenu, child: child);

  /// 点高亮文字：显示并修改备注，也可以换颜色、取消高亮。
  Future<void> _editNote(ReplaceRule rule) async {
    final controller = TextEditingController(text: RuleNotes.get(widget.aid, rule.id));
    var color = rule.color;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(rule.label),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: controller, autofocus: true, minLines: 3, maxLines: 8, decoration: const InputDecoration(hintText: '写点备注：身份、关系、伏笔……')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in ruleColors)
                      GestureDetector(
                        onTap: () => setLocal(() => color = c),
                        child: Container(width: 28, height: 28, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(width: color == c ? 3 : 0, color: Theme.of(context).colorScheme.onSurface))),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (rule.aid.isNotEmpty) TextButton(onPressed: () => Navigator.pop(context, 'remove'), child: const Text('取消高亮')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (result == null) return;
    final rules = ReplaceRules.all();
    if (result == 'remove') {
      await ReplaceRules.save([for (final r in rules) if (r.id != rule.id) r]);
      await RuleNotes.set(widget.aid, rule.id, '');
    } else {
      await RuleNotes.set(widget.aid, rule.id, controller.text);
      if (color != rule.color) await ReplaceRules.save([for (final r in rules) r.id == rule.id ? r.copyWith(color: color) : r]);
    }
    ref.invalidate(chapterProvider);
    if (mounted) setState(() {});
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
    // 章节一加载好就预加载后面几章（用 read 触发，且每章只触发一次）
    if (index >= 0 && content.hasValue) {
      for (final ahead in chapters.skip(index + 1).take(_prefetch)) {
        if (_preloaded.add(ahead.cid)) {
          Future.microtask(() {
            if (mounted) ref.read(chapterProvider((widget.aid, ahead.cid)));
          });
        }
      }
    }

    final title = index >= 0 ? chapters[index].title : '';
    _bookTitle = novel?.detail.title;
    _chapterTitle = title;
    final f = FontStore.resolve(prefs.font);
    final style = readerStyle(prefs, palette.fg, family: f.family, fallback: f.fallback);
    final noted = RuleNotes.of(widget.aid).keys.toSet();

    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) => _onKey(e, prev, next, prefs.mode),
      child: Scaffold(
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
              final reading = _speaking && prefs.ttsHighlight && _si < _segs.length && _ttsText == c.text ? _segs[_si] : null;
              InlineSpan spanOf(int from, int to) => buildSpan(c, from, to, style, noted, reading, Theme.of(context).colorScheme.primary);
              final key = ValueKey((_cid, _epoch, prefs.mode, prefs.font, prefs.fontSize, prefs.lineHeight, prefs.margin, c.marks.length, c.text.length));
              void onMark(Mark m) => _editNote(m.rule);
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
                      follow: reading?.$1,
                      nav: _nav,
                      hasSelection: () => _hasSelection,
                    )
                  : PagedBody(
                      key: key,
                      chapter: c,
                      spanOf: spanOf,
                      style: style,
                      margin: prefs.margin,
                      title: title,
                      curl: prefs.mode >= 2,
                      cover: prefs.mode == 3,
                      dual: prefs.dual,
                      status: _status,
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
                      follow: reading?.$1,
                      nav: _nav,
                      hasSelection: () => _hasSelection,
                    );
            },
          ),
          if (prefs.mode == 0 && content.hasValue)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: ColoredBox(
                  color: palette.bg,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(prefs.margin, 6, prefs.margin, MediaQuery.viewPaddingOf(context).bottom + 8),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _pos,
                      builder: (_, pos, _) {
                        final len = content.value!.text.length;
                        return ReaderFooter(status: _status, right: '${len == 0 ? 0 : (pos * 100 ~/ len).clamp(0, 100)}%', style: TextStyle(fontSize: 11, color: palette.fg.withValues(alpha: 0.5)));
                      },
                    ),
                  ),
                ),
              ),
            ),
          if (_bar) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: palette.bg,
                elevation: 2,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(icon: Icon(Icons.arrow_back, color: palette.fg), onPressed: () => context.pop()),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: palette.fg)),
                            if (_bookTitle != null) Text(_bookTitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.fg.withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Material(
                color: palette.bg,
                elevation: 2,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(tooltip: '上一章', color: palette.fg, disabledColor: palette.fg.withValues(alpha: 0.3), icon: const Icon(Icons.chevron_left), onPressed: prev == null ? null : () => _go(prev.cid)),
                          if (chapters.length > 1) ...[
                            Text('${index + 1}/${chapters.length}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.fg)),
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
                          ] else
                            const Spacer(),
                          IconButton(tooltip: '下一章', color: palette.fg, disabledColor: palette.fg.withValues(alpha: 0.3), icon: const Icon(Icons.chevron_right), onPressed: next == null ? null : () => _go(next.cid)),
                        ],
                      ),
                      Row(
                        children: [
                          for (final (icon, label, onTap) in <(IconData, String, VoidCallback)>[
                            (Icons.menu_book_outlined, '目录', () => _showCatalogue(novel?.catalogue ?? const [], _cid)),
                            (Bookmarks.has(widget.aid, _cid, _offset) ? Icons.bookmark : Icons.bookmark_border, '书签', _addBookmark),
                            (_speaking ? Icons.stop_circle_outlined : Icons.record_voice_over_outlined, _speaking ? '停止' : '朗读', () => _speaking ? _stopTts() : content.whenData(_startTts)),
                            (Icons.tune, '朗读设置', _showTtsSettings),
                            (Icons.settings_outlined, '设置', _showSettings),
                          ])
                            Expanded(
                              child: InkWell(
                                onTap: onTap,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 22, color: palette.fg), const SizedBox(height: 2), Text(label, style: TextStyle(fontSize: 11, color: palette.fg))]),
                                ),
                              ),
                            ),
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
      ),
    );
  }

  static const _prefetch = 2;
  final _preloaded = <String>{};

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
                        final rules = ReplaceRules.all().where((r) => r.kind == RuleKind.highlight && notes.containsKey(r.id) && (r.aid.isEmpty || r.aid == widget.aid)).toList();
                        return rules.isEmpty
                            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('还没有备注。\n选中文字点"高亮"，之后点一下高亮的字就能写备注。', textAlign: TextAlign.center)))
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

  void _showTtsSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final prefs = ref.watch(readerPrefsProvider);
          void set(ReaderPrefs p) {
            ref.read(readerPrefsProvider.notifier).update(p);
            if (_speaking) _applyTtsPrefs();
          }

          // 定时关闭不在 prefs 里，用一次无变化的更新让这个面板重画
          void sleep(DateTime? at, bool chapterEnd) {
            _sleepAt = at;
            _stopAtChapterEnd = chapterEnd;
            ref.read(readerPrefsProvider.notifier).update(prefs.copyWith());
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_speaking)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        OutlinedButton.icon(onPressed: () => _skipSentence(-1), icon: const Icon(Icons.skip_previous), label: const Text('上一句')),
                        OutlinedButton.icon(onPressed: () => _skipSentence(1), icon: const Icon(Icons.skip_next), label: const Text('下一句')),
                      ],
                    ),
                  Text('语速 ${prefs.ttsRate.toStringAsFixed(1)}'),
                  Slider(min: 0.1, max: 1.0, divisions: 9, value: prefs.ttsRate, onChanged: (v) => set(prefs.copyWith(ttsRate: v))),
                  Text('音调 ${prefs.ttsPitch.toStringAsFixed(1)}'),
                  Slider(min: 0.5, max: 2.0, divisions: 15, value: prefs.ttsPitch, onChanged: (v) => set(prefs.copyWith(ttsPitch: v))),
                  const Text('声音'),
                  FutureBuilder<List<String>>(
                    future: _zhVoices(),
                    builder: (context, snap) {
                      final names = snap.data ?? const <String>[];
                      return Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(label: const Text('系统默认'), selected: prefs.ttsVoice.isEmpty, onSelected: (_) => set(prefs.copyWith(ttsVoice: ''))),
                          for (final n in names) ChoiceChip(label: Text(n), selected: prefs.ttsVoice == n, onSelected: (_) => set(prefs.copyWith(ttsVoice: n))),
                        ],
                      );
                    },
                  ),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('高亮正在读的句子，并跟着翻页'), value: prefs.ttsHighlight, onChanged: (v) => set(prefs.copyWith(ttsHighlight: v))),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('读完一章自动读下一章'), value: prefs.ttsAutoNext, onChanged: (v) => set(prefs.copyWith(ttsAutoNext: v))),
                  const Text('定时关闭'),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(label: const Text('关'), selected: _sleepAt == null && !_stopAtChapterEnd, onSelected: (_) => sleep(null, false)),
                      for (final m in [15, 30, 60])
                        ChoiceChip(label: Text('$m 分钟'), selected: false, onSelected: (_) => sleep(DateTime.now().add(Duration(minutes: m)), false)),
                      ChoiceChip(label: const Text('读完本章'), selected: _stopAtChapterEnd, onSelected: (_) => sleep(null, true)),
                    ],
                  ),
                  if (_sleepAt != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('将在 ${_sleepAt!.hour.toString().padLeft(2, '0')}:${_sleepAt!.minute.toString().padLeft(2, '0')} 停止', style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 系统里的中文语音名（引擎不支持列出时返回空）。
  Future<List<String>> _zhVoices() async {
    try {
      final voices = await _tts.getVoices as List?;
      return [
        for (final v in voices ?? const [])
          if (v is Map && '${v['locale']}'.toLowerCase().startsWith('zh')) '${v['name']}',
      ];
    } catch (_) {
      return const [];
    }
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
                    segments: const [ButtonSegment(value: 0, label: Text('滚动')), ButtonSegment(value: 1, label: Text('滑动')), ButtonSegment(value: 2, label: Text('仿真')), ButtonSegment(value: 3, label: Text('覆盖'))],
                    selected: {prefs.mode},
                    onSelectionChanged: (s) => set(prefs.copyWith(mode: s.first)),
                  ),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('宽屏双页'), subtitle: const Text('窗口宽度 ≥ 900 时，左右翻页模式一屏显示两页'), value: prefs.dual, onChanged: (v) => set(prefs.copyWith(dual: v))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
