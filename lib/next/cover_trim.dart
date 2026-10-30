import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 封面四周的白边：框出来的封面常常带上旁边的白底（封面比框窄、框得不够准），扫描图本身也常有一圈白边。
/// 图片解码成长边不超过 [maxSide] 的小图来找，够准也够快。
class CoverPixels {
  CoverPixels(this.rgba, this.w, this.h);

  final Uint8List rgba;
  final int w, h;

  static Future<CoverPixels> decode(Uint8List bytes, {int maxSide = 600}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final s = math.min(1.0, maxSide / math.max(desc.width, desc.height));
    final codec = await desc.instantiateCodec(targetWidth: math.max(1, (desc.width * s).round()), targetHeight: math.max(1, (desc.height * s).round()));
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final px = CoverPixels(data!.buffer.asUint8List(), image.width, image.height);
    image.dispose();
    codec.dispose();
    desc.dispose();
    buffer.dispose();
    return px;
  }

  /// 把 [crop]（0~1 比例）四边的空白往里收掉，每边最多收 [maxTrim]（免得把本来就是白底的封面削掉一大块）。
  /// 没有白边原样返回 [crop]。
  ui.Rect trim(ui.Rect crop, {double maxTrim = 0.15}) {
    final x0 = (crop.left * w).round().clamp(0, w - 1), x1 = (crop.right * w).round().clamp(x0 + 1, w);
    final y0 = (crop.top * h).round().clamp(0, h - 1), y1 = (crop.bottom * h).round().clamp(y0 + 1, h);
    final maxX = ((x1 - x0) * maxTrim).floor(), maxY = ((y1 - y0) * maxTrim).floor();
    // 先收左右（白边多在左右），再用收过的宽度收上下
    var l = 0, r = 0, t = 0, b = 0;
    while (l < maxX && _blank(x0 + l, x0 + l + 1, y0, y1)) {
      l++;
    }
    while (r < maxX && _blank(x1 - r - 1, x1 - r, y0, y1)) {
      r++;
    }
    while (t < maxY && _blank(x0 + l, x1 - r, y0 + t, y0 + t + 1)) {
      t++;
    }
    while (b < maxY && _blank(x0 + l, x1 - r, y1 - b - 1, y1 - b)) {
      b++;
    }
    // 两三个像素的不算（缩小、压缩糊出来的），不值得改裁剪框
    int real(int n) => n < 3 ? 0 : n + 1; // 收了的再多收 1 像素：白边到画面之间那条过渡的浅色
    l = real(l);
    r = real(r);
    t = real(t);
    b = real(b);
    if (l + r + t + b == 0) return crop;
    return ui.Rect.fromLTRB((x0 + l) / w, (y0 + t) / h, (x1 - r) / w, (y1 - b) / h);
  }

  /// [xa, xb) × [ya, yb) 这一条是不是空白：整体很亮（白、浅灰），而且几乎所有像素都和平均色差不多
  bool _blank(int xa, int xb, int ya, int yb) {
    var n = 0, sr = 0, sg = 0, sb = 0;
    for (var y = ya; y < yb; y++) {
      for (var x = xa; x < xb; x++) {
        final i = (y * w + x) * 4;
        sr += rgba[i];
        sg += rgba[i + 1];
        sb += rgba[i + 2];
        n++;
      }
    }
    if (n == 0) return false;
    final mr = sr / n, mg = sg / n, mb = sb / n;
    if (0.299 * mr + 0.587 * mg + 0.114 * mb < 200) return false;
    var off = 0;
    for (var y = ya; y < yb; y++) {
      for (var x = xa; x < xb; x++) {
        final i = (y * w + x) * 4;
        if ((rgba[i] - mr).abs() > 20 || (rgba[i + 1] - mg).abs() > 20 || (rgba[i + 2] - mb).abs() > 20) off++;
      }
    }
    return off <= n * 0.04;
  }
}
