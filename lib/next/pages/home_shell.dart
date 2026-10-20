import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 主界面框架：窄屏底部导航，宽屏（平板、电脑、网页）左侧导航。
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _items = [(Icons.auto_stories_outlined, Icons.auto_stories, '书架'), (Icons.person_outline, Icons.person, '我的')];

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
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
                for (final (icon, selected, label) in _items) NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            destinations: [for (final (icon, selected, label) in _items) NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label)],
          ),
        ],
      ),
    );
  }
}
