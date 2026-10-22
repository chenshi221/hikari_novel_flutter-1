import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/cat_volume.dart';
import '../cover_color.dart';
import '../library.dart';
import '../progress.dart';
import '../read_state.dart';
import '../router.dart';
import '../stats.dart';
import '../volumes.dart';
import '../widgets.dart';
import 'cover_picker_page.dart';
import 'novel_page.dart';

/// 书架"卷册"模式点进来：一本书的各卷叠在一起，左右滑把某一卷转到最前面；点最前面那卷展开它的详情和目录。
class VolumesPage extends ConsumerStatefulWidget {
  const VolumesPage({super.key, required this.aid});

  final String aid;

  @override
  ConsumerState<VolumesPage> createState() => _VolumesPageState();
}

/// 正在读第几卷：阅读进度所在的那卷；那卷已经读完（比如手动标了读完）就往后找第一卷没读完的。
/// 没读过、或者从那卷往后全读完了为 -1。
int readingVolume(String aid) {
  final p = ReadingProgress.of(aid);
  final i = p == null ? -1 : Volumes.indexOf(aid, p.cid);
  if (i < 0) return -1;
  final vols = Volumes.of(aid);
  final done = Volumes.done(aid);
  for (var j = i; j < vols.length; j++) {
    if (!done.containsKey(vols[j].title)) return j;
  }
  return -1;
}

class _VolumesPageState extends ConsumerState<VolumesPage> {
  late int _cur = math.max(readingVolume(widget.aid), 0); // 一打开停在正在读的那卷
  late final _pc = PageController(initialPage: _cur, viewportFraction: 0.5);
  bool _open = false;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  double get _page => _pc.hasClients && _pc.position.haveDimensions ? _pc.page ?? _cur.toDouble() : _cur.toDouble();

  void _tap(int i, Vol v) {
    if (i != _cur) {
      _pc.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    } else {
      setState(() => _open = !_open);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aid = widget.aid;
    ref.watch(volumeChangesProvider);
    final novel = ref.watch(novelProvider(aid)).value; // 顺带把目录存下来，也用来显示章节名
    final vols = Volumes.of(aid);
    final title = novel?.detail.title ?? (LibraryStore.get(aid)?['title'] as String?) ?? ReadingStats.info(aid).title;
    final fallback = novel?.detail.imgUrl ?? (LibraryStore.get(aid)?['img'] as String?) ?? '';
    final queue = ref.read(volumeCoverQueueProvider);
    String coverOf(Vol v) => queue.volCover(aid, v, fallback);

    final cur = math.min(_cur, math.max(vols.length - 1, 0));
    final cover = vols.isEmpty ? fallback : coverOf(vols[cur]);
    final base = ref.watch(coverColorProvider(cover)).value ?? savedCoverColor(cover) ?? kNeutralCoverColor;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    final Widget body;
    if (vols.isEmpty) {
      body = novel == null ? const Center(child: CircularProgressIndicator(color: Colors.white)) : const StatePanel(title: '这本书没有分卷信息');
    } else {
      final v = vols[cur];
      final carousel = _Carousel(
        aid: aid,
        vols: vols,
        controller: _pc,
        page: () => _page,
        cur: cur,
        coverOf: coverOf,
        onPage: (i) => setState(() => _cur = i),
        onTap: _tap,
        onLongPress: (v) => pickVolumeCover(context, aid, v),
      );
      final scrubber = vols.length > 6
          ? SliderTheme(
              data: SliderTheme.of(
                context,
              ).copyWith(activeTrackColor: Colors.white, inactiveTrackColor: Colors.white24, thumbColor: Colors.white, valueIndicatorColor: Colors.black87),
              child: Slider(
                value: cur.toDouble(),
                max: vols.length - 1.0,
                divisions: vols.length - 1,
                label: '第 ${cur + 1} 卷',
                onChanged: (x) => _pc.jumpToPage(x.round()),
              ),
            )
          : const SizedBox(height: 16);
      final summary = _Summary(aid: aid, vol: v, index: cur, count: vols.length);
      final details = _Details(
        key: ValueKey(v.title),
        aid: aid,
        vol: v,
        index: cur,
        chapterTitles: {
          for (final cv in novel?.catalogue ?? const <CatVolume>[])
            for (final c in cv.chapters) c.cid: c.title,
        },
      );
      body = wide
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: carousel),
                      scrubber,
                      summary,
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  child: _open ? SizedBox(width: 400, child: details) : const SizedBox(height: double.infinity),
                ),
              ],
            )
          : LayoutBuilder(
              builder: (context, c) => Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    height: c.maxHeight * (_open ? 0.42 : 0.68),
                    child: carousel,
                  ),
                  scrubber,
                  Expanded(
                    child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: _open ? details : summary),
                  ),
                ],
              ),
            );
    }

    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _open = false); // 返回键先收起详情
      },
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: base),
        duration: const Duration(milliseconds: 400),
        builder: (context, color, child) => Scaffold(backgroundColor: color, body: child),
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                actions: [IconButton(tooltip: '书籍详情', icon: const Icon(Icons.info_outline), onPressed: () => context.push(Routes.novel(aid)))],
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// 叠在一起的卷封面：最前面的最大，越往两边越小、越往后压，越暗。
/// 封面自己画（按离当前页的距离排先后），上面盖一层透明的 PageView 只管滑动和点击。
class _Carousel extends StatelessWidget {
  const _Carousel({
    required this.aid,
    required this.vols,
    required this.controller,
    required this.page,
    required this.cur,
    required this.coverOf,
    required this.onPage,
    required this.onTap,
    required this.onLongPress,
  });

  final String aid;
  final List<Vol> vols;
  final PageController controller;
  final double Function() page;
  final int cur;
  final String Function(Vol) coverOf;
  final ValueChanged<int> onPage;
  final void Function(int, Vol) onTap;
  final ValueChanged<Vol> onLongPress;

  @override
  Widget build(BuildContext context) {
    final done = Volumes.done(aid);
    final read = ReadState.read(aid);
    final reading = readingVolume(aid);
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight * 0.92;
        final w = math.min(h * kCoverAspect, c.maxWidth * 0.72);
        return Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final p = page();
                final shown = [for (var i = math.max(0, p.floor() - 3); i <= math.min(vols.length - 1, p.ceil() + 3); i++) i]
                  ..sort((a, b) => (b - p).abs().compareTo((a - p).abs())); // 远的先画，近的压在上面
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final i in shown)
                      Builder(
                        builder: (context) {
                          final d = i - p;
                          final a = d.abs();
                          // 第一张错开大半个身位，再往后的只露一条边
                          final dx = d.sign * (w * 0.55 * math.min(a, 1) + w * 0.16 * math.max(a - 1, 0));
                          final v = vols[i];
                          final card = _VolumeCard(
                            url: coverOf(v),
                            width: w,
                            done: done.containsKey(v.title),
                            reading: i == reading,
                            untouched: !v.cids.any(read.contains),
                            shade: math.min(a, 1.5) * 0.3,
                          );
                          return Opacity(
                            opacity: (3.2 - a).clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(dx, 0),
                              child: Transform.scale(
                                scale: 1 - 0.14 * math.min(a, 2.5),
                                child: i == cur ? Hero(tag: 'vols:$aid', child: card) : card,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
            PageView.builder(
              controller: controller,
              itemCount: vols.length,
              onPageChanged: onPage,
              itemBuilder: (context, i) =>
                  GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onTap(i, vols[i]), onLongPress: () => onLongPress(vols[i])),
            ),
          ],
        );
      },
    );
  }
}

/// 一卷的封面，带状态：读完了打勾，正在读的有"在读"标签，一章都没读的暗一点。
class _VolumeCard extends StatelessWidget {
  const _VolumeCard({required this.url, required this.width, required this.done, required this.reading, required this.untouched, required this.shade});

  final String url;
  final double width;
  final bool done;
  final bool reading;
  final bool untouched;

  /// 离最前面越远越暗（0~1）
  final double shade;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width / kCoverAspect,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 12))],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.white.withValues(alpha: 0.15)),
          NetImage(url, error: const Icon(Icons.menu_book_outlined, color: Colors.white54)),
          ColoredBox(color: Colors.black.withValues(alpha: (shade + (untouched ? 0.2 : 0)).clamp(0, 0.75))),
          if (reading)
            Positioned(
              top: 10,
              left: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                ),
                child: Text(
                  '在读',
                  style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (done)
            const Positioned(
              right: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(Icons.check_circle, color: Color(0xFF2E9E5B), size: 26),
              ),
            ),
        ],
      ),
    ),
  );
}

String _progress(String aid, Vol v) {
  final read = ReadState.read(aid);
  final at = Volumes.done(aid)[v.title];
  final d = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
  return ['已读 ${v.textCids.where(read.contains).length} / ${v.textCids.length} 章', if (d != null) '${d.year}.${d.month}.${d.day} 读完'].join(' · ');
}

/// 没展开时封面下面的一行：卷名和进度
class _Summary extends StatelessWidget {
  const _Summary({required this.aid, required this.vol, required this.index, required this.count});

  final String aid;
  final Vol vol;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      children: [
        Text(
          vol.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '第 ${index + 1} / $count 卷 · ${_progress(aid, vol)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 12),
        const Text('点封面看这一卷 · 长按换封面', style: TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    ),
  );
}

/// 展开后的这一卷：进度、评分、继续读、换封面、阅读报告，以及这一卷的目录。
class _Details extends StatefulWidget {
  const _Details({super.key, required this.aid, required this.vol, required this.index, required this.chapterTitles});

  final String aid;
  final Vol vol;
  final int index;
  final Map<String, String> chapterTitles;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  @override
  Widget build(BuildContext context) {
    final aid = widget.aid;
    final v = widget.vol;
    final read = ReadState.read(aid);
    final p = ReadingProgress.of(aid);
    final inVol = p != null && v.cids.contains(p.cid);
    final next = inVol ? p.cid : v.textCids.where((c) => !read.contains(c)).firstOrNull ?? v.cids.first;
    final label = inVol ? '继续读' : (v.textCids.every(read.contains) ? '重读这一卷' : '开始读');
    final rating = Volumes.rating(aid, v.title);
    const muted = TextStyle(color: Colors.white60);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Material(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              v.title,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(_progress(aid, v), style: muted),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  GestureDetector(
                    onTap: () async {
                      await Volumes.setRating(aid, v.title, rating == i ? 0 : i); // 再点一次当前星数就取消
                      if (mounted) setState(() {});
                    },
                    child: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFFFC53D), size: 28),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(onPressed: () => context.push(Routes.reader(aid, next)), icon: const Icon(Icons.play_arrow), label: Text(label)),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: '换封面',
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  onPressed: () => pickVolumeCover(context, aid, v),
                  icon: const Icon(Icons.image_outlined),
                ),
                IconButton.outlined(
                  tooltip: '阅读报告',
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  onPressed: () => context.push(Routes.report(aid, vol: widget.index)),
                  icon: const Icon(Icons.insights),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final (i, cid) in v.cids.indexed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: read.contains(cid) ? const Icon(Icons.check, size: 16, color: Colors.white38) : const SizedBox(width: 16),
                title: Text(
                  widget.chapterTitles[cid] ?? '第 ${i + 1} 章',
                  style: TextStyle(
                    color: cid == p?.cid ? Colors.white : (read.contains(cid) ? Colors.white38 : Colors.white70),
                    fontWeight: cid == p?.cid ? FontWeight.w700 : null,
                  ),
                ),
                trailing: cid == p?.cid ? const Text('读到这里', style: TextStyle(color: Colors.white, fontSize: 12)) : null,
                onTap: () => context.push(Routes.reader(aid, cid)),
              ),
          ],
        ),
      ),
    );
  }
}
