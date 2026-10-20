import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';

/// 游客看到需要账号的内容时显示的提示，点按钮再去登录。
class LoginPrompt extends StatelessWidget {
  const LoginPrompt({super.key, required this.title, this.detail = '登录轻小说文库账号后即可使用。'});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.push(Routes.login), child: const Text('去登录')),
          ],
        ),
      ),
    );
  }
}
