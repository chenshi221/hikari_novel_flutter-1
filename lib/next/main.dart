import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'cache.dart';
import 'fonts.dart';
import 'session.dart';

/// 新框架的入口（重构中，与旧 App 并存）。
///
/// - 原生：`flutter run -t lib/next/main.dart`
/// - 网页预览：`flutter run -d web-server -t lib/next/main.dart`，并在同一台机器上运行 `tool/preview_proxy.dart`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SessionStore.open();
  await ChapterCache.open();
  await FontStore.loadSaved();
  runApp(ProviderScope(overrides: [sessionStoreProvider.overrideWithValue(store)], child: const NextApp()));
}
