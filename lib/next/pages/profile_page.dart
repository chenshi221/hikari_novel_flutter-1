import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../env.dart';
import '../router.dart';
import '../session.dart';
import '../settings.dart';
import '../theme.dart';
import '../theme_art.dart';

/// 自己选的头像：只保存在本机（wenku8 的头像要在网站上改，这里不改网站上的）。
class _AvatarController extends Notifier<String?> {
  @override
  String? build() => Hive.box('session').get('avatar') as String?;

  Future<void> pick() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    final src = file?.path;
    if (src == null) return;
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'avatar'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final dest = await File(src).copy(p.join(dir.path, 'avatar_${DateTime.now().millisecondsSinceEpoch}${p.extension(src)}'));
    await Hive.box('session').put('avatar', dest.path);
    state = dest.path;
  }

  Future<void> clear() async {
    await Hive.box('session').delete('avatar');
    state = null;
  }
}

final avatarProvider = NotifierProvider<_AvatarController, String?>(_AvatarController.new);

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

  void _avatarMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                ref.read(avatarProvider.notifier).pick();
              },
            ),
            if (ref.read(avatarProvider) != null)
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('恢复网站头像'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(avatarProvider.notifier).clear();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final custom = ref.watch(avatarProvider);
    final palette = appPalettes[ref.watch(paletteProvider)];
    final theme = Theme.of(context);
    final user = session is SessionLoggedIn ? session.user : null;

    Widget entry(IconData icon, String title, String route) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(
      child: ListTile(leading: Icon(icon), title: Text(title), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(route)),
    ));

    final name = user?.username ?? '未登录';
    final avatar = CircleAvatar(
      radius: 30,
      backgroundColor: theme.colorScheme.surfaceContainer,
      foregroundImage: custom != null && !isWebPreview
          ? FileImage(File(custom))
          : (user == null || user.avatar.isEmpty ? null : NetworkImage(displayImageUrl(user.avatar.replaceFirst('http://', 'https://')))),
      child: Text(name.characters.firstOrNull ?? '?', style: theme.textTheme.titleLarge),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (palette.art != null)
            ThemeBanner(
              palette: palette,
              child: Row(
                children: [
                  isWebPreview || user == null ? avatar : GestureDetector(onTap: () => _avatarMenu(context, ref), child: avatar),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: user == null ? () => context.push(Routes.login) : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
                          Text(user == null ? '点击登录' : (session is SessionLoggedIn && session.offline ? 'UID ${user.uid} · 离线' : 'UID ${user.uid}'), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: isWebPreview || user == null ? avatar : GestureDetector(onTap: () => _avatarMenu(context, ref), child: avatar),
                title: Text(name, style: theme.textTheme.headlineSmall),
                subtitle: Text(user == null ? '点击登录' : (session is SessionLoggedIn && session.offline ? 'UID ${user.uid} · 离线' : 'UID ${user.uid}')),
                onTap: user == null ? () => context.push(Routes.login) : null,
              ),
            ),
          const SizedBox(height: 16),
          entry(Icons.bar_chart_outlined, '阅读统计', Routes.stats),
          entry(Icons.history, '阅读历史', Routes.history),
          entry(Icons.bookmark_border, '书签', Routes.bookmarks),
          entry(Icons.download_outlined, '离线缓存', Routes.cache),
          entry(Icons.settings_outlined, '设置', Routes.settings),
          if (user != null) ...[const SizedBox(height: 24), OutlinedButton(onPressed: () => _confirmLogout(context, ref), child: const Text('退出登录'))],
        ],
      ),
    );
  }
}
