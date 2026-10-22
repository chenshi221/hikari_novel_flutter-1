import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/wenku8/wenku8_parser.dart';
import '../read_state.dart';
import '../stats.dart';
import '../theme.dart';
import '../widgets.dart';

String _duration(int seconds) => seconds >= 3600 ? '${seconds ~/ 3600}时 ${(seconds % 3600) ~/ 60}分' : '${(seconds / 60).ceil()}分';

String _chars(int n) => n >= 10000 ? '${(n / 10000).toStringAsFixed(1)} 万' : '$n';

String _date(String key) => key.replaceAll('-', '.');

const _ratingLabels = ['点星星评分', '不推荐', '一般', '还不错', '值得一读', '神作必读'];

/// 一本书的阅读报告：封面、阅读时间、已读字数、已读天数、起止日期和自己的评分，可以保存成图片分享。
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key, required this.aid});

  final String aid;

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  final _shot = GlobalKey();
  late int _rating = ReadState.rating(widget.aid);

  Future<void> _share(String title) async {
    try {
      final boundary = _shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final file = File('${(await getTemporaryDirectory()).path}/report_${widget.aid}.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: '《$title》阅读报告'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分享失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final aid = widget.aid;
    final meta = ReadingStats.meta(aid);
    final title = meta?.title ?? '书号 $aid';
    final img = (meta?.img.isNotEmpty ?? false) ? meta!.img : Wenku8Parser.coverUrl(aid);
    final seconds = ReadingStats.perBook()[aid] ?? 0;
    final days = ReadingStats.bookDays(aid);
    final accent = Theme.of(context).colorScheme.primary;
    final base = Color.lerp(accent, Colors.black, 0.6)!;
    final width = MediaQuery.sizeOf(context).width;

    Widget tile(IconData icon, String label, Widget value) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 16, color: Colors.white70), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))]),
          const SizedBox(height: 10),
          value,
        ],
      ),
    );
    const big = TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700);

    return Scaffold(
      backgroundColor: base,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [IconButton(tooltip: '保存为图片并分享', icon: const Icon(Icons.ios_share), onPressed: () => _share(title))],
      ),
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: _shot,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: base),
                      ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28), child: Opacity(opacity: 0.55, child: NetImage(img))),
                      DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [base.withValues(alpha: 0.2), base.withValues(alpha: 0.75), base]))),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 72, 20, 32),
                child: Column(
                  children: [
                    Container(
                      width: width * 0.52,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 28, offset: const Offset(0, 14))]),
                      child: AspectRatio(aspectRatio: 3 / 4, child: CoverImage(img)),
                    ),
                    const SizedBox(height: 28),
                    Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600, fontFamilyFallback: kSerifFallback)),
                    if ((meta?.author ?? '').isNotEmpty) ...[const SizedBox(height: 6), Text(meta!.author, style: const TextStyle(color: Colors.white70, fontSize: 16))],
                    const SizedBox(height: 28),
                    // 两张卡片等高；在滚动区域里高度没有上限，stretch 必须配 IntrinsicHeight，否则整页布局失败
                    IntrinsicHeight(
                      child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: tile(
                            Icons.auto_awesome,
                            _ratingLabels[_rating],
                            Row(
                              children: [
                                for (var i = 1; i <= 5; i++)
                                  GestureDetector(
                                    onTap: () {
                                      // 再点一次当前星数就取消评分
                                      final v = _rating == i ? 0 : i;
                                      ReadState.setRating(aid, v);
                                      setState(() => _rating = v);
                                    },
                                    child: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFFFC53D), size: 22),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(flex: 5, child: tile(Icons.hourglass_bottom, '阅读时间', Text(seconds == 0 ? '—' : _duration(seconds), style: big))),
                      ],
                    ),
                    ),
                    const SizedBox(height: 12),
                    IntrinsicHeight(
                      child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: tile(Icons.text_fields, '已读字数', Text(_chars(ReadState.readChars(aid)), style: big))),
                        const SizedBox(width: 12),
                        Expanded(child: tile(Icons.calendar_today_outlined, '已读天数', Text('${days.length} 天', style: big))),
                      ],
                    ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: tile(Icons.schedule, '阅读日期（开始 / 结束）', Text(days.isEmpty ? '—' : '${_date(days.first)} - ${_date(days.last).substring(5)}', style: big.copyWith(fontSize: 20))),
                    ),
                    const SizedBox(height: 28),
                    const Text('该报告由 Hikari Novel 统计生成', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
