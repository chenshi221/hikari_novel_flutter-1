import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/common/wenku8_node.dart';
import 'package:go_router/go_router.dart';

import '../env.dart';
import '../router.dart';
import '../theme.dart';
import '../session.dart';
import '../settings.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(sessionStoreProvider);
    final mode = ref.watch(themeModeProvider);
    final prefs = ref.watch(readerPrefsProvider);
    final palette = ref.watch(paletteProvider);
    final theme = Theme.of(context);
    Widget section(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 20, 4, 8), child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)));

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          section('外观'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
              ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
              ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, p) in appPalettes.indexed)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: p.light, radius: 8),
                  label: Text(p.name),
                  selected: palette == i,
                  onSelected: (_) => ref.read(paletteProvider.notifier).set(i),
                ),
            ],
          ),
          section('阅读'),
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 0, label: Text('滚动')), ButtonSegment(value: 1, label: Text('滑动')), ButtonSegment(value: 2, label: Text('仿真'))],
            selected: {prefs.mode},
            onSelectionChanged: (s) => ref.read(readerPrefsProvider.notifier).update(prefs.copyWith(mode: s.first)),
          ),
          const SizedBox(height: 8),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('正则替换'), subtitle: const Text('去广告、统一用字'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.rules)),
          Text('字号 ${prefs.fontSize.round()}'),
          Slider(min: 14, max: 32, divisions: 18, value: prefs.fontSize, onChanged: (v) => ref.read(readerPrefsProvider.notifier).update(prefs.copyWith(fontSize: v))),
          Text('朗读语速 ${prefs.ttsRate.toStringAsFixed(1)}'),
          Slider(min: 0.1, max: 1.0, divisions: 9, value: prefs.ttsRate, onChanged: (v) => ref.read(readerPrefsProvider.notifier).update(prefs.copyWith(ttsRate: v))),
          if (!isWebPreview) ...[
            section('网络'),
            SegmentedButton<Wenku8Node>(
              segments: const [
                ButtonSegment(value: Wenku8Node.wwwWenku8Net, label: Text('wenku8.net')),
                ButtonSegment(value: Wenku8Node.wwwWenku8Cc, label: Text('wenku8.cc')),
              ],
              selected: {store.node},
              onSelectionChanged: (s) async {
                await store.setNode(s.first);
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: store.proxy,
              decoration: const InputDecoration(labelText: 'HTTP 代理', hintText: '127.0.0.1:7890'),
              onChanged: store.setProxy,
            ),
          ],
          section('关于'),
          FutureBuilder(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => ListTile(contentPadding: EdgeInsets.zero, title: const Text('Hikari Novel'), subtitle: Text('轻小说文库第三方客户端 · MIT${snap.hasData ? ' · v${snap.data!.version}+${snap.data!.buildNumber}' : ''}')),
          ),
        ],
      ),
    );
  }
}
