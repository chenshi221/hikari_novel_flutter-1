import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'image_cache.dart';

/// 从封面像素（RGBA）算阅读报告的背景色，像豆瓣那样：取整体色调，压低饱和度、调暗，白字看得清。
/// 饱和的像素权重大一些，免得大片白底把颜色冲淡成灰。
Color tintFrom(Uint8List rgba) {
  var r = 0.0, g = 0.0, b = 0.0, w = 0.0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final pr = rgba[i] / 255, pg = rgba[i + 1] / 255, pb = rgba[i + 2] / 255;
    final weight = 0.15 + (math.max(pr, math.max(pg, pb)) - math.min(pr, math.min(pg, pb)));
    r += pr * weight;
    g += pg * weight;
    b += pb * weight;
    w += weight;
  }
  if (w == 0) return const Color(0xFF4A4A4A);
  final hsl = HSLColor.fromColor(Color.fromARGB(255, (r / w * 255).round(), (g / w * 255).round(), (b / w * 255).round()));
  return hsl.withSaturation(hsl.saturation.clamp(0.12, 0.35)).withLightness(0.38).toColor();
}

/// 封面背景色，按地址存在本机，算过一次就不再解码。
final coverColorProvider = FutureProvider.family<Color, String>((ref, url) async {
  final box = Hive.box('session');
  final saved = (box.get('ccolor') as Map?)?[url] as int?;
  if (saved != null) return Color(saved);
  final bytes = await ref.read(imageStoreProvider).load(url);
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24);
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  final color = tintFrom(data!.buffer.asUint8List());
  await box.put('ccolor', {...((box.get('ccolor') as Map?) ?? const {}), url: color.toARGB32()});
  return color;
});
