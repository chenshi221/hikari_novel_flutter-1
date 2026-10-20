import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

Box get _box => Hive.box('session');

/// 深浅色：跟随系统 / 浅色 / 深色，记在本地。
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.values[(_box.get('themeMode') as int?) ?? 0];

  void set(ThemeMode mode) {
    _box.put('themeMode', mode.index);
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// 阅读器的外观和翻页方式。
class ReaderPrefs {
  const ReaderPrefs({this.fontSize = 19, this.lineHeight = 1.8, this.theme = 0, this.paged = false});

  final double fontSize;
  final double lineHeight;

  /// 阅读背景：0 纸张 1 护眼 2 夜间 3 跟随应用
  final int theme;

  /// false 上下滚动，true 左右翻页
  final bool paged;

  ReaderPrefs copyWith({double? fontSize, double? lineHeight, int? theme, bool? paged}) =>
      ReaderPrefs(fontSize: fontSize ?? this.fontSize, lineHeight: lineHeight ?? this.lineHeight, theme: theme ?? this.theme, paged: paged ?? this.paged);
}

class ReaderPrefsController extends Notifier<ReaderPrefs> {
  @override
  ReaderPrefs build() => ReaderPrefs(
    fontSize: (_box.get('r.fontSize') as num?)?.toDouble() ?? 19,
    lineHeight: (_box.get('r.lineHeight') as num?)?.toDouble() ?? 1.8,
    theme: (_box.get('r.theme') as int?) ?? 0,
    paged: (_box.get('r.paged') as bool?) ?? false,
  );

  void update(ReaderPrefs next) {
    _box.putAll({'r.fontSize': next.fontSize, 'r.lineHeight': next.lineHeight, 'r.theme': next.theme, 'r.paged': next.paged});
    state = next;
  }
}

final readerPrefsProvider = NotifierProvider<ReaderPrefsController, ReaderPrefs>(ReaderPrefsController.new);
