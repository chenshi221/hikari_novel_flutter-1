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

/// 配色方案：只换强调色，底色保持同一套暖色。
class AppPalette {
  const AppPalette(this.name, this.light, this.dark);

  final String name;
  final Color light;
  final Color dark;
}

const appPalettes = [
  AppPalette('陶土', AppColors.terracotta, AppColors.terracottaLight),
  AppPalette('靛蓝', Color(0xFF3D5A9B), Color(0xFF8FA8E0)),
  AppPalette('森绿', Color(0xFF4A7C59), Color(0xFF8DBB9A)),
  AppPalette('玫瑰', Color(0xFFB04A6B), Color(0xFFE08CA5)),
  AppPalette('琥珀', Color(0xFFB07A1E), Color(0xFFE2B45E)),
  AppPalette('石墨', Color(0xFF4B4A47), Color(0xFFC2C0B6)),
];

ThemeData buildAppTheme(Brightness brightness, [AppPalette palette = const AppPalette('陶土', AppColors.terracotta, AppColors.terracottaLight)]) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? palette.dark : palette.light,
    onPrimary: Colors.white,
    secondary: dark ? AppColors.paperSoft : AppColors.inkSoft,
    onSecondary: dark ? AppColors.night : AppColors.cream,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: dark ? AppColors.night : AppColors.cream,
    onSurface: dark ? AppColors.paper : AppColors.ink,
    onSurfaceVariant: dark ? AppColors.paperSoft : AppColors.inkSoft,
    surfaceContainerLowest: dark ? AppColors.night : Colors.white,
    surfaceContainerLow: dark ? AppColors.nightRaised : AppColors.creamDeep,
    surfaceContainer: dark ? AppColors.nightRaised : AppColors.creamDeep,
    surfaceContainerHigh: dark ? AppColors.nightRaised : AppColors.creamDeep,
    outline: dark ? AppColors.lineDark : AppColors.line,
    outlineVariant: dark ? AppColors.lineDark : AppColors.line,
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
      color: dark ? AppColors.nightRaised : Colors.white,
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
      fillColor: dark ? AppColors.nightRaised : Colors.white,
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
