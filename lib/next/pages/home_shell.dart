import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../session.dart';
import '../updates.dart';

/// 主界面框架：窄屏底部导航，宽屏（平板、电脑、网页）左侧导航。
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _items = [(Icons.explore_outlined, Icons.explore, '发现'), (Icons.auto_stories_outlined, Icons.auto_stories, '书架'), (Icons.update_outlined, Icons.update, '更新'), (Icons.person_outline, Icons.person, '我的')];

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final offline = session is SessionLoggedIn && session.offline;
    final unread = UpdateStore.unread();
    Widget icon(IconData data, String label) => label == '更新' && unread > 0 ? Badge(label: Text('$unread'), child: Icon(data)) : Icon(data);
    final body = Column(
      children: [
        if (offline)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: InkWell(
              onTap: () => ref.read(sessionProvider.notifier).restore(),
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Row(children: [Icon(Icons.cloud_off_outlined, size: 16), SizedBox(width: 8), Expanded(child: Text('离线模式，显示的是已保存的内容，点这里重新连接', style: TextStyle(fontSize: 12)))])),
            ),
          ),
        Expanded(child: shell),
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
                for (final (i, selected, label) in _items) NavigationRailDestination(icon: icon(i, label), selectedIcon: icon(selected, label), label: Text(label)),
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
            destinations: [for (final (i, selected, label) in _items) NavigationDestination(icon: icon(i, label), selectedIcon: icon(selected, label), label: label)],
          ),
        ],
      ),
    );
  }
}
