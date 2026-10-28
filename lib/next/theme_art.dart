import 'package:flutter/material.dart';

import 'theme.dart';
import 'theme_squire.dart';

/// 角色主题和插画主题的美术：底部导航的 Q 版图标（"我的"页右上的立绘直接用 assets/theme/`art`_full.png）。普通配色没有这些，返回 null 走默认图标。
class ThemeArt {
  const ThemeArt._();

  static Widget? navIcon(AppPalette palette, int index, {required bool selected}) {
    if (palette.scene) return RuinsNavIcon(index, selected: selected);
    final art = palette.art;
    if (art == null) return null;
    return AnimatedScale(
      scale: selected ? 1.15 : 0.92,
      duration: const Duration(milliseconds: 160),
      child: Opacity(opacity: selected ? 1 : 0.65, child: Image.asset('assets/theme/${art}_$index.png', width: 30, height: 30)),
    );
  }
}
