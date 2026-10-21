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

/// 配色方案编号（theme.dart 的 appPalettes）。
class PaletteController extends Notifier<int> {
  @override
  int build() => (_box.get('palette') as int?) ?? 0;

  void set(int index) {
    _box.put('palette', index);
    state = index;
  }
}

final paletteProvider = NotifierProvider<PaletteController, int>(PaletteController.new);

/// 阅读器的外观和翻页方式。
class ReaderPrefs {
  const ReaderPrefs({this.fontSize = 19, this.lineHeight = 1.8, this.theme = 0, this.mode = 0, this.ttsRate = 0.5, this.margin = 22, this.font = 0, this.ttsPitch = 1.0, this.ttsVoice = '', this.ttsHighlight = true, this.ttsAutoNext = true, this.dual = true, this.dim = 0});

  final double fontSize;
  final double lineHeight;

  /// 阅读背景：0 纸张 1 护眼 2 夜间 3 跟随应用
  final int theme;

  /// 翻页方式：0 上下滚动 1 左右滑动 2 仿真翻页 3 覆盖翻页
  final int mode;

  /// 字体：0 系统默认 1 衬线 2 自选字体文件
  final int font;

  /// 左右页边距
  final double margin;

  /// 朗读语速 0.1~1.0
  final double ttsRate;

  /// 朗读音调 0.5~2.0
  final double ttsPitch;

  /// 朗读声音（系统语音名），留空用系统默认
  final String ttsVoice;

  /// 朗读时高亮正在读的句子，并跟着翻页
  final bool ttsHighlight;

  /// 读完一章自动读下一章
  final bool ttsAutoNext;

  /// 宽屏（窗口宽度 ≥ 900）时左右翻页模式显示双页
  final bool dual;

  /// 阅读亮度遮罩的不透明度 0~0.7，0 为不遮
  final double dim;

  ReaderPrefs copyWith({double? fontSize, double? lineHeight, int? theme, int? mode, double? ttsRate, double? margin, int? font, double? ttsPitch, String? ttsVoice, bool? ttsHighlight, bool? ttsAutoNext, bool? dual, double? dim}) => ReaderPrefs(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    theme: theme ?? this.theme,
    mode: mode ?? this.mode,
    ttsRate: ttsRate ?? this.ttsRate,
    margin: margin ?? this.margin,
    font: font ?? this.font,
    ttsPitch: ttsPitch ?? this.ttsPitch,
    ttsVoice: ttsVoice ?? this.ttsVoice,
    ttsHighlight: ttsHighlight ?? this.ttsHighlight,
    ttsAutoNext: ttsAutoNext ?? this.ttsAutoNext,
    dual: dual ?? this.dual,
    dim: dim ?? this.dim,
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
    margin: (_box.get('r.margin') as num?)?.toDouble() ?? 22,
    font: (_box.get('r.font') as int?) ?? 0,
    ttsPitch: (_box.get('r.ttsPitch') as num?)?.toDouble() ?? 1.0,
    ttsVoice: (_box.get('r.ttsVoice') as String?) ?? '',
    ttsHighlight: (_box.get('r.ttsHighlight') as bool?) ?? true,
    ttsAutoNext: (_box.get('r.ttsAutoNext') as bool?) ?? true,
    dual: (_box.get('r.dual') as bool?) ?? true,
    dim: (_box.get('r.dim') as num?)?.toDouble() ?? 0,
  );

  void update(ReaderPrefs next) {
    _box.putAll({'r.fontSize': next.fontSize, 'r.lineHeight': next.lineHeight, 'r.theme': next.theme, 'r.mode': next.mode, 'r.ttsRate': next.ttsRate, 'r.margin': next.margin, 'r.font': next.font, 'r.ttsPitch': next.ttsPitch, 'r.ttsVoice': next.ttsVoice, 'r.ttsHighlight': next.ttsHighlight, 'r.ttsAutoNext': next.ttsAutoNext, 'r.dual': next.dual, 'r.dim': next.dim});
    state = next;
  }
}

final readerPrefsProvider = NotifierProvider<ReaderPrefsController, ReaderPrefs>(ReaderPrefsController.new);
