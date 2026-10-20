import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../env.dart';
import '../router.dart';
import '../session.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后以游客身份浏览，书架等功能需要重新登录。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session is! SessionLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: const CircleAvatar(radius: 30, child: Icon(Icons.person_outline)),
                title: const Text('未登录'),
                subtitle: const Text('点击登录'),
                onTap: () => context.push(Routes.login),
              ),
            ),
            const SizedBox(height: 16),
            Card(child: ListTile(leading: const Icon(Icons.bar_chart_outlined), title: const Text('阅读统计'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.stats))),
          Card(child: ListTile(leading: const Icon(Icons.history), title: const Text('阅读历史'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.history))),
          Card(child: ListTile(leading: const Icon(Icons.download_outlined), title: const Text('离线缓存'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.cache))),
          Card(child: ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('设置'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.settings))),
          ],
        ),
      );
    }
    final user = session.user;
    final theme = Theme.of(context);

    final rows = [
      ('等级', user.userLevel),
      ('积分', user.point),
      ('经验', user.experience),
      ('贡献', user.contribution),
      ('注册日期', user.registerDate),
      ('书架上限', user.maxBookshelfNum),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: theme.colorScheme.surfaceContainer,
                    foregroundImage: user.avatar.isEmpty ? null : NetworkImage(displayImageUrl(user.avatar.replaceFirst('http://', 'https://'))),
                    child: Text(user.username.characters.firstOrNull ?? '?', style: theme.textTheme.titleLarge),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.username, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text('UID ${user.uid}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final (i, (label, value)) in rows.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(label),
                    trailing: Text(value.isEmpty ? '-' : value, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(child: ListTile(leading: const Icon(Icons.history), title: const Text('阅读历史'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.history))),
          Card(child: ListTile(leading: const Icon(Icons.download_outlined), title: const Text('离线缓存'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.cache))),
          Card(child: ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('设置'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.settings))),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: () => _confirmLogout(context, ref), child: const Text('退出登录')),
        ],
      ),
    );
  }
}
