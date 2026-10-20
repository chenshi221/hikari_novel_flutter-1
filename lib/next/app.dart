import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'settings.dart';
import 'theme.dart';

class NextApp extends ConsumerWidget {
  const NextApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Hikari Novel',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light, appPalettes[ref.watch(paletteProvider)]),
      darkTheme: buildAppTheme(Brightness.dark, appPalettes[ref.watch(paletteProvider)]),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
