import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env.dart';
import '../session.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后需要重新登录才能使用。'),
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
    if (session is! SessionLoggedIn) return const SizedBox.shrink();
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
          OutlinedButton(onPressed: () => _confirmLogout(context, ref), child: const Text('退出登录')),
        ],
      ),
    );
  }
}
