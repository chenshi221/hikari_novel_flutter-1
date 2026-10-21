import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync.dart';

/// 同步设置：坚果云（或其他 WebDAV）。应用密码在坚果云网页端"账户信息 → 安全选项 → 第三方应用管理"里生成。
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  final _url = TextEditingController(text: Sync.url);
  final _user = TextEditingController(text: Sync.user);
  final _pass = TextEditingController();
  final _folder = TextEditingController(text: Sync.folder);
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Sync.password().then((p) {
      if (mounted) _pass.text = p;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _folder.dispose();
    super.dispose();
  }

  Future<void> _save() => Sync.save(url: _url.text, user: _user.text, pass: _pass.text, folder: _folder.text);

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      await _save();
      await Sync.test();
      _note = '连接成功';
    } catch (e) {
      _note = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncProvider);
    final theme = Theme.of(context);
    final last = Sync.lastSync;
    return Scaffold(
      appBar: AppBar(title: const Text('同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('在多台设备上填同一个账号和文件夹，进度、书签、历史、已读章节、规则备注和阅读统计会互相合并。章节缓存和外观设置不同步。', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(controller: _url, decoration: const InputDecoration(labelText: 'WebDAV 地址'), keyboardType: TextInputType.url),
          const SizedBox(height: 12),
          TextField(controller: _user, decoration: const InputDecoration(labelText: '账号（坚果云注册邮箱）'), autocorrect: false),
          const SizedBox(height: 12),
          TextField(controller: _pass, decoration: const InputDecoration(labelText: '应用密码（不是登录密码）'), obscureText: true),
          const SizedBox(height: 12),
          TextField(controller: _folder, decoration: const InputDecoration(labelText: '同步文件夹', helperText: '会在 WebDAV 根目录下自动创建')),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: _busy || status.busy ? null : _test, child: const Text('测试连接'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy || status.busy
                      ? null
                      : () async {
                          await _save();
                          await ref.read(syncProvider.notifier).run();
                        },
                  child: status.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('立即同步'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_note != null) Text(_note!),
          if (status.message != null) Text(status.message!),
          if (last > 0) Text('上次同步：${DateTime.fromMillisecondsSinceEpoch(last)}'.split('.').first, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Text('已配置后，App 进入后台时会自动同步一次（3 分钟内不重复）。密码优先存在系统钥匙串，不可用时存在本机应用数据里。', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text('删除不会同步：在一台设备上删掉的书签、规则，另一台同步时会再带回来。', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
