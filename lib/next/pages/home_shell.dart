import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../env.dart';
import '../image_cache.dart';
import '../library.dart';
import '../router.dart';
import '../session.dart';
import '../settings.dart';
import '../sync.dart';
import '../theme.dart';
import '../theme_art.dart';
import '../updates.dart';

/// 主界面框架：窄屏底部导航，宽屏（平板、电脑、网页）左侧导航。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  Timer? _timer;

  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    // 打开时强制检查一次更新，之后应用在前台时每小时一次（进了后台 Dart 定时器基本不会触发）
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_syncAndCheck);
    Sync.auto();
    if (!isWebPreview) ref.read(imageStoreProvider).trim().ignore();
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _checkUpdates());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 进后台时把 cookie jar 里服务端续期过的 cookie 写回本地
    if (state == AppLifecycleState.paused) {
      ref.read(sessionProvider.notifier).persistCookies();
      Sync.auto();
    } else if (state == AppLifecycleState.resumed) {
      Sync.auto();
      ref.read(libraryProvider.notifier).sync(); // 距上次不到 30 分钟会跳过
    }
  }

  /// 本地书架里有书、而且不是离线状态才检查（游客也能用本地书架追更新）。
  void _checkUpdates() {
    final s = ref.read(sessionProvider);
    final online = s is SessionLoggedOut || (s is SessionLoggedIn && !s.offline);
    if (online && ref.read(libraryProvider).books.isNotEmpty) ref.read(updateProvider.notifier).refresh();
  }

  /// 先和网站书架同步（可能导入新书），再检查更新。
  Future<void> _syncAndCheck() async {
    await ref.read(libraryProvider.notifier).sync();
    _checkUpdates();
  }

  static const _items = [(Icons.explore_outlined, Icons.explore, '发现'), (Icons.auto_stories_outlined, Icons.auto_stories, '书架'), (Icons.update_outlined, Icons.update, '更新'), (Icons.person_outline, Icons.person, '我的')];

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (prev, next) {
      if (prev is! SessionLoggedIn && next is SessionLoggedIn && !next.offline) _syncAndCheck();
    });
    ref.watch(updateProvider);
    final session = ref.watch(sessionProvider);
    final needsVerify = (session is SessionLoggedIn && session.needsVerify) || (session is SessionLoggedOut && session.needsVerify);
    final offline = (session is SessionLoggedIn && session.offline) || needsVerify;
    final unread = UpdateStore.unread();
    final palette = appPalettes[ref.watch(paletteProvider)];
    Widget icon(int i, bool selected) {
      final (outlined, filled, label) = _items[i];
      final art = ThemeArt.navIcon(palette, i, selected: selected) ?? Icon(selected ? filled : outlined);
      return label == '更新' && unread > 0 ? Badge(label: Text('$unread'), child: art) : art;
    }

    final body = Column(
      children: [
        if (offline)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: InkWell(
              onTap: () => needsVerify ? context.push(Routes.verify) : ref.read(sessionProvider.notifier).restore(),
              child: SafeArea(
                bottom: false,
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Row(children: [const Icon(Icons.cloud_off_outlined, size: 16), const SizedBox(width: 8), Expanded(child: Text(needsVerify ? '被网站的验证拦住了，点这里去验证' : '离线模式，显示的是已保存的内容，点这里重新连接', style: const TextStyle(fontSize: 12)))])),
              ),
            ),
          ),
        // 提示条已经让开了状态栏，下面的页面就别再留一次
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: offline, child: shell)),
      ],
    );
    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              backgroundColor: Theme.of(context).colorScheme.surface,
              indicatorColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
              destinations: [
                for (final (i, item) in _items.indexed) NavigationRailDestination(icon: icon(i, false), selectedIcon: icon(i, true), label: Text(item.$3)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            destinations: [for (final (i, item) in _items.indexed) NavigationDestination(icon: icon(i, false), selectedIcon: icon(i, true), label: item.$3)],
          ),
        ],
      ),
    );
  }
}
