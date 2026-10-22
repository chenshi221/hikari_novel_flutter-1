import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache.dart';
import '../data.dart';
import '../image_cache.dart';
import '../volumes.dart';
import '../widgets.dart';

/// 封面框的宽高比（文库的封面大多是这个比例）
const kCoverAspect = 0.7;

/// 自选卷封面：列出这卷插图章节里的图，选一张后框出封面那一块（横版展开图只框右边的封面）。
Future<void> pickVolumeCover(BuildContext context, String aid, Vol v) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => _PickerPage(aid: aid, vol: v),
  ),
);

class _PickerPage extends ConsumerStatefulWidget {
  const _PickerPage({required this.aid, required this.vol});

  final String aid;
  final Vol vol;

  @override
  ConsumerState<_PickerPage> createState() => _PickerPageState();
}

class _PickerPageState extends ConsumerState<_PickerPage> {
  late Future<List<String>> _images = _load();

  /// 插图章节缓存过就直接用，没缓存就联网取一次并存下
  Future<List<String>> _load() async {
    final cid = widget.vol.illus;
    if (cid == null) return const [];
    var content = await ChapterCache.get(widget.aid, cid);
    if (content == null) {
      content = await ref.read(apiProvider).chapter(widget.aid, cid);
      await ChapterCache.put(widget.aid, cid, content);
    }
    return content.images;
  }

  Future<void> _pick(String url) async {
    final picked = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => _CropPage(url: url)));
    if (picked == null) return;
    await Volumes.setCover(widget.aid, widget.vol.title, picked);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final current = splitCrop(Volumes.cover(widget.aid, widget.vol.title) ?? '').url;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('选封面 · ${widget.vol.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () async {
              await Volumes.resetCover(widget.aid, widget.vol.title);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('恢复自动'),
          ),
        ],
      ),
      body: FutureBuilder<List<String>>(
        future: _images,
        builder: (context, snap) {
          if (snap.hasError) return StatePanel(title: '插图加载失败', detail: '${snap.error}', error: snap.error, onRetry: () => setState(() => _images = _load()));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final images = snap.data!;
          if (images.isEmpty) return const StatePanel(title: '这一卷没有插图', detail: '目录里没有插图章节，只能用书的封面。');
          return contentWidth(
            CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  sliver: SliverToBoxAdapter(
                    child: Text('选一张图，再框出封面那一块', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverLayoutBuilder(
                    builder: (context, c) => SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: (c.crossAxisExtent / 130).floor().clamp(3, 6),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: kCoverAspect,
                      ),
                      itemCount: images.length,
                      itemBuilder: (context, i) => InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _pick(images[i]),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: images[i] == current ? Border.all(color: theme.colorScheme.primary, width: 3) : null,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: NetImage(images[i], fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 框出封面：框固定不动，拖动、双指缩放图片，把封面放进框里。返回带裁剪框的地址（见 [withCrop]）。
class _CropPage extends ConsumerStatefulWidget {
  const _CropPage({required this.url});

  final String url;

  @override
  ConsumerState<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends ConsumerState<_CropPage> {
  final _tc = TransformationController();
  late final Future<(Uint8List, ui.Size)> _image = () async {
    final bytes = await ref.read(imageStoreProvider).load(widget.url);
    return (bytes, await imageSize(bytes));
  }();
  Size? _laidOut; // 按哪个框的大小摆过初始位置

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  /// 图片在框里铺满（像 BoxFit.cover）时的大小
  static Size _fill(ui.Size img, Size frame) {
    final s = math.max(frame.width / img.width, frame.height / img.height);
    return Size(img.width * s, img.height * s);
  }

  /// 框里现在露出的是图片的哪一块（0~1 比例）
  Rect _visible(ui.Size img, Size frame) {
    final child = _fill(img, frame);
    final scale = _tc.value.getMaxScaleOnAxis();
    final t = _tc.value.getTranslation();
    final r = Rect.fromLTWH(-t.x / scale / child.width, -t.y / scale / child.height, frame.width / scale / child.width, frame.height / scale / child.height);
    return Rect.fromLTRB(r.left.clamp(0, 1), r.top.clamp(0, 1), r.right.clamp(0, 1), r.bottom.clamp(0, 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('框出封面', style: TextStyle(color: Colors.white)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, widget.url), child: const Text('用整张'))],
      ),
      body: FutureBuilder<(Uint8List, ui.Size)>(
        future: _image,
        builder: (context, snap) {
          if (snap.hasError) return const StatePanel(title: '图片加载失败', detail: '检查网络后再试一次。');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (bytes, img) = snap.data!;
          return LayoutBuilder(
            builder: (context, c) {
              final w = math.min(c.maxWidth - 48, (c.maxHeight - 140) * kCoverAspect);
              final frame = Size(w, w / kCoverAspect);
              final child = _fill(img, frame);
              if (_laidOut != frame) {
                _laidOut = frame;
                // 横版展开图（封底 + 书脊 + 封面）的封面在右边，一开始就对准右边；竖图居中
                final dx = img.width > img.height ? frame.width - child.width : (frame.width - child.width) / 2;
                _tc.value = Matrix4.translationValues(dx, (frame.height - child.height) / 2, 0);
              }
              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SizedBox.fromSize(
                        size: frame,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            InteractiveViewer(
                              transformationController: _tc,
                              constrained: false,
                              minScale: 1,
                              maxScale: 6,
                              clipBehavior: Clip.none,
                              child: SizedBox.fromSize(
                                size: child,
                                child: Image.memory(bytes, fit: BoxFit.fill),
                              ),
                            ),
                            // 框外压暗，框线
                            IgnorePointer(
                              child: CustomPaint(size: frame, painter: _FramePainter()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('拖动、双指缩放，把封面放进框里', style: TextStyle(color: Colors.white70)),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)), // 主题默认按钮占满整行，这里要和文字并排
                          onPressed: () {
                            final r = _visible(img, frame);
                            Navigator.pop(context, r.width > 0.995 && r.height > 0.995 ? widget.url : withCrop(widget.url, r));
                          },
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    // 画一圈很大的暗色，中间挖掉框
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(frame.inflate(4000))
        ..addRect(frame),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    canvas.drawRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => false;
}
