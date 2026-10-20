import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/common/wenku8_node.dart';
import '../env.dart';
import '../session.dart';
import 'login_webview_page.dart';

/// 登录页。未登录时整个 App 只能看到这一页。
///
/// - 原生 App：打开 wenku8 自己的登录网页（能处理验证、记住登录等），登录后读取 cookie
/// - 网页预览：浏览器里没法嵌入别的网站，改为账号密码表单，由服务器上的转发程序提交
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWebLogin() async {
    final store = ref.read(sessionStoreProvider);
    final cookie = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => LoginWebViewPage(loginUrl: '${store.node.node}/login.php')));
    if (cookie != null) await _run(() => ref.read(sessionProvider.notifier).loginWithCookie(cookie));
  }

  Future<void> _submitPassword() => _run(() => ref.read(sessionProvider.notifier).loginWithPassword(_username.text.trim(), _password.text));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final notice = _error ?? (session is SessionLoggedOut ? session.message : null);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/images/logo_transparent.png', height: 72, alignment: Alignment.centerLeft),
                  const SizedBox(height: 28),
                  Text('欢迎回来', style: theme.textTheme.displaySmall),
                  const SizedBox(height: 10),
                  Text('登录轻小说文库账号后继续阅读。', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 32),
                  if (isWebPreview) ..._passwordForm(theme) else ..._nativeLogin(theme),
                  if (notice != null) ...[const SizedBox(height: 16), _Notice(text: notice)],
                  const SizedBox(height: 32),
                  Text('登录有效期请选择"一天"及以上，"临时登录"无法保持登录状态。', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _nativeLogin(ThemeData theme) {
    final store = ref.read(sessionStoreProvider);
    return [
      Text('线路', style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      SegmentedButton<Wenku8Node>(
        segments: const [
          ButtonSegment(value: Wenku8Node.wwwWenku8Net, label: Text('wenku8.net')),
          ButtonSegment(value: Wenku8Node.wwwWenku8Cc, label: Text('wenku8.cc')),
        ],
        selected: {store.node},
        onSelectionChanged: _busy
            ? null
            : (s) async {
                await store.setNode(s.first);
                setState(() {});
              },
      ),
      const SizedBox(height: 24),
      FilledButton(onPressed: _busy ? null : _openWebLogin, child: _busy ? const _ButtonSpinner() : const Text('登录轻小说文库')),
    ];
  }

  List<Widget> _passwordForm(ThemeData theme) => [
    TextField(
      controller: _username,
      enabled: !_busy,
      decoration: const InputDecoration(labelText: '用户名'),
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.username],
    ),
    const SizedBox(height: 14),
    TextField(
      controller: _password,
      enabled: !_busy,
      obscureText: true,
      decoration: const InputDecoration(labelText: '密码'),
      autofillHints: const [AutofillHints.password],
      onSubmitted: (_) => _submitPassword(),
    ),
    const SizedBox(height: 24),
    FilledButton(onPressed: _busy ? null : _submitPassword, child: _busy ? const _ButtonSpinner() : const Text('登录')),
    const SizedBox(height: 8),
    Text('预览版：账号密码由你的服务器转交给轻小说文库，不会经过其他地方。', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
  ];
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: scheme.primary)),
    );
  }
}
