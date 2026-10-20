import 'package:flutter/material.dart';

/// "Claude 风格"配色：暖米白底、陶土橙强调色、暖深灰暗色模式。
class AppColors {
  const AppColors._();

  static const terracotta = Color(0xFFC96442);
  static const terracottaLight = Color(0xFFD97757);

  // 浅色
  static const cream = Color(0xFFFAF9F5);
  static const creamDeep = Color(0xFFF0EEE6);
  static const ink = Color(0xFF141413);
  static const inkSoft = Color(0xFF5E5D59);
  static const line = Color(0xFFE3DFD3);

  // 深色
  static const night = Color(0xFF262624);
  static const nightRaised = Color(0xFF30302E);
  static const paper = Color(0xFFFAF9F5);
  static const paperSoft = Color(0xFFC2C0B6);
  static const lineDark = Color(0xFF3E3E3A);
}

/// 标题用衬线体；没有安装时依次回退到系统宋体。
const List<String> kSerifFallback = ['Noto Serif SC', 'Source Han Serif SC', 'Songti SC', 'STSong', 'serif'];

/// 配色方案：强调色 + 浅色 / 深色各一套底色，整个界面（背景、卡片、边框、导航）都跟着换。
class AppPalette {
  const AppPalette(this.name, this.accentLight, this.accentDark, {required this.bgLight, required this.cardLight, required this.lineLight, required this.bgDark, required this.cardDark, required this.lineDark});

  final String name;
  final Color accentLight, accentDark;
  final Color bgLight, cardLight, lineLight;
  final Color bgDark, cardDark, lineDark;

  Color accent(bool dark) => dark ? accentDark : accentLight;
  Color bg(bool dark) => dark ? bgDark : bgLight;
  Color card(bool dark) => dark ? cardDark : cardLight;
  Color line(bool dark) => dark ? lineDark : lineLight;
}

const appPalettes = [
  AppPalette('陶土', AppColors.terracotta, AppColors.terracottaLight, bgLight: AppColors.cream, cardLight: AppColors.creamDeep, lineLight: AppColors.line, bgDark: AppColors.night, cardDark: AppColors.nightRaised, lineDark: AppColors.lineDark),
  AppPalette('靛蓝', Color(0xFF3D5A9B), Color(0xFF8FA8E0), bgLight: Color(0xFFF4F6FB), cardLight: Color(0xFFE5EAF5), lineLight: Color(0xFFD3DAEA), bgDark: Color(0xFF181C27), cardDark: Color(0xFF242A3A), lineDark: Color(0xFF353C52)),
  AppPalette('森绿', Color(0xFF4A7C59), Color(0xFF8DBB9A), bgLight: Color(0xFFF4F7F2), cardLight: Color(0xFFE4ECDF), lineLight: Color(0xFFD1DDCB), bgDark: Color(0xFF171D18), cardDark: Color(0xFF232B25), lineDark: Color(0xFF34402F)),
  AppPalette('玫瑰', Color(0xFFB04A6B), Color(0xFFE08CA5), bgLight: Color(0xFFFBF5F6), cardLight: Color(0xFFF3E3E7), lineLight: Color(0xFFE8D0D6), bgDark: Color(0xFF211A1D), cardDark: Color(0xFF30262A), lineDark: Color(0xFF463539)),
  AppPalette('琥珀', Color(0xFFB07A1E), Color(0xFFE2B45E), bgLight: Color(0xFFFAF6EC), cardLight: Color(0xFFF1E8D2), lineLight: Color(0xFFE3D6B5), bgDark: Color(0xFF1F1B12), cardDark: Color(0xFF2D271A), lineDark: Color(0xFF43392A)),
  AppPalette('石墨', Color(0xFF4B4A47), Color(0xFFC2C0B6), bgLight: Color(0xFFF3F3F2), cardLight: Color(0xFFE6E6E4), lineLight: Color(0xFFD5D5D2), bgDark: Color(0xFF121212), cardDark: Color(0xFF1E1E1E), lineDark: Color(0xFF333333)),
];

ThemeData buildAppTheme(Brightness brightness, [AppPalette palette = const AppPalette('陶土', AppColors.terracotta, AppColors.terracottaLight, bgLight: AppColors.cream, cardLight: AppColors.creamDeep, lineLight: AppColors.line, bgDark: AppColors.night, cardDark: AppColors.nightRaised, lineDark: AppColors.lineDark)]) {
  final dark = brightness == Brightness.dark;
  final bg = palette.bg(dark);
  final card = palette.card(dark);
  final line = palette.line(dark);
  final raised = dark ? card : Colors.white;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: palette.accent(dark),
    onPrimary: dark && palette.name == '石墨' ? Colors.black : Colors.white,
    secondary: dark ? AppColors.paperSoft : AppColors.inkSoft,
    onSecondary: dark ? AppColors.night : AppColors.cream,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: bg,
    onSurface: dark ? AppColors.paper : AppColors.ink,
    onSurfaceVariant: dark ? AppColors.paperSoft : AppColors.inkSoft,
    surfaceContainerLowest: raised,
    surfaceContainerLow: card,
    surfaceContainer: card,
    surfaceContainerHigh: card,
    outline: line,
    outlineVariant: line,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: scheme.surface);
  final serif = base.textTheme.apply(fontFamilyFallback: kSerifFallback);

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: serif.displaySmall?.copyWith(fontWeight: FontWeight.w500, letterSpacing: -0.5),
      headlineMedium: serif.headlineMedium?.copyWith(fontWeight: FontWeight.w500),
      headlineSmall: serif.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
      titleLarge: serif.titleLarge?.copyWith(fontWeight: FontWeight.w500),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: serif.titleLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w500),
    ),
    cardTheme: CardThemeData(
      color: raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: raised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(color: scheme.outline, thickness: 1, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
