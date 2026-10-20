import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session.dart';
import '../widgets.dart';

/// 发现页。内容（排行、分类、搜索）在第 2 阶段做，目前只是占位。
class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(sessionProvider) is SessionLoggedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('发现')),
      body: loggedIn ? const Center(child: Text('排行、分类和搜索即将上线')) : const LoginPrompt(title: '登录后浏览书库'),
    );
  }
}
