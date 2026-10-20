import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session.dart';

/// 启动页：检查登录状态。检查失败（多半是网络问题）时提供重试和重新登录。
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo_transparent.png', height: 96),
                const SizedBox(height: 24),
                Text('Hikari Novel', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 32),
                if (state is SessionCheckFailed) ...[
                  Text('连不上轻小说文库', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    state.message,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: () => ref.read(sessionProvider.notifier).restore(), child: const Text('重试')),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => ref.read(sessionProvider.notifier).logout(), child: const Text('重新登录')),
                ] else
                  SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
