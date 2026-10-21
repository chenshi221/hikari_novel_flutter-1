import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 角色主题的美术：底部导航的 Q 版图标、"我的"页顶部的角色横幅。普通配色没有这些，返回 null 走默认图标。
class ThemeArt {
  const ThemeArt._();

  static Widget? navIcon(AppPalette palette, int index, {required bool selected}) {
    final art = palette.art;
    if (art == null) return null;
    return AnimatedScale(
      scale: selected ? 1.15 : 0.92,
      duration: const Duration(milliseconds: 160),
      child: Opacity(opacity: selected ? 1 : 0.65, child: Image.asset('assets/theme/${art}_$index.png', width: 30, height: 30)),
    );
  }
}

/// "我的"页顶部：主题色渐变 + 几何小装饰（三角、圆环、网点）+ 角色立绘，文字放在左边。
class ThemeBanner extends StatelessWidget {
  const ThemeBanner({super.key, required this.palette, required this.child});

  final AppPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = palette.accent(dark), b = palette.secondary ?? a;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 168,
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a.withValues(alpha: dark ? 0.45 : 0.28), b.withValues(alpha: dark ? 0.35 : 0.22)])),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _DecoPainter(a, b))),
            Positioned(right: -6, bottom: 0, top: 6, child: Image.asset('assets/theme/${palette.art}_full.png', fit: BoxFit.contain)),
            Positioned(left: 16, right: 130, top: 0, bottom: 0, child: Align(alignment: Alignment.centerLeft, child: child)),
          ],
        ),
      ),
    );
  }
}

class _DecoPainter extends CustomPainter {
  const _DecoPainter(this.a, this.b);

  final Color a, b;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = b.withValues(alpha: 0.35);
    final line = Paint()
      ..color = a.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // 三角
    final tri = Path()
      ..moveTo(size.width * 0.52, size.height * 0.12)
      ..lineTo(size.width * 0.60, size.height * 0.34)
      ..lineTo(size.width * 0.44, size.height * 0.34)
      ..close();
    canvas.drawPath(tri, line);
    // 圆环
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.22), 26, line);
    // 网点
    for (var i = 0; i < 5; i++) {
      for (var j = 0; j < 4; j++) {
        canvas.drawCircle(Offset(10 + i * 9.0, size.height - 12 - j * 9.0), 1.8, fill);
      }
    }
    // 斜纹
    for (var i = 0; i < 4; i++) {
      final x = size.width * 0.6 + i * 9;
      canvas.drawLine(Offset(x, size.height), Offset(x + 22 * math.sqrt1_2, size.height - 22 * math.sqrt1_2), line..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_DecoPainter old) => old.a != a || old.b != b;
}
