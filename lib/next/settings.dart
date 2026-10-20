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
  const ReaderPrefs({this.fontSize = 19, this.lineHeight = 1.8, this.theme = 0, this.mode = 0, this.ttsRate = 0.5});

  final double fontSize;
  final double lineHeight;

  /// 阅读背景：0 纸张 1 护眼 2 夜间 3 跟随应用
  final int theme;

  /// 翻页方式：0 上下滚动 1 左右滑动 2 仿真翻页
  final int mode;

  /// 朗读语速 0.1~1.0
  final double ttsRate;

  ReaderPrefs copyWith({double? fontSize, double? lineHeight, int? theme, int? mode, double? ttsRate}) => ReaderPrefs(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    theme: theme ?? this.theme,
    mode: mode ?? this.mode,
    ttsRate: ttsRate ?? this.ttsRate,
  );
}

class ReaderPrefsController extends Notifier<ReaderPrefs> {
  @override
  ReaderPrefs build() => ReaderPrefs(
    fontSize: (_box.get('r.fontSize') as num?)?.toDouble() ?? 19,
    lineHeight: (_box.get('r.lineHeight') as num?)?.toDouble() ?? 1.8,
    theme: (_box.get('r.theme') as int?) ?? 0,
    mode: (_box.get('r.mode') as int?) ?? 0,
    ttsRate: (_box.get('r.ttsRate') as num?)?.toDouble() ?? 0.5,
  );

  void update(ReaderPrefs next) {
    _box.putAll({'r.fontSize': next.fontSize, 'r.lineHeight': next.lineHeight, 'r.theme': next.theme, 'r.mode': next.mode, 'r.ttsRate': next.ttsRate});
    state = next;
  }
}

final readerPrefsProvider = NotifierProvider<ReaderPrefsController, ReaderPrefs>(ReaderPrefsController.new);
