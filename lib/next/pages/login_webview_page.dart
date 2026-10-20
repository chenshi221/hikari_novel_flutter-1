import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../common/constants.dart';

/// 原生 App 的登录：wenku8 有 Cloudflare 验证，Dart 的 HTTP 请求过不去，所以让真正的浏览器引擎
/// 打开登录页（需要时用户可以直接在页面里完成验证），页面加载好后把用户名、密码、有效期填进表单并提交。
/// 登录成功（出现 jieqiUserInfo cookie）后关闭页面，返回该站点的全部 cookie 字符串。
class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key, required this.loginUrl, required this.username, required this.password, required this.keepSeconds});

  final String loginUrl;
  final String username;
  final String password;
  final int keepSeconds;

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  final _cookieManager = CookieManager.instance();
  bool _ready = false;
  bool _done = false;
  bool _submitted = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    // 先清掉旧 cookie，避免带着过期的登录状态进入
    _cookieManager.deleteAllCookies().whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  /// 找到带密码框的表单，填值后提交。返回 false 表示当前页面没有登录表单（例如还在验证页）。
  Future<bool> _fillAndSubmit(InAppWebViewController c) async {
    final js = '''
(() => {
  const pass = document.querySelector('input[name=password]');
  const form = pass && pass.form;
  if (!form) return false;
  form.querySelector('input[name=username]').value = ${jsonEncode(widget.username)};
  pass.value = ${jsonEncode(widget.password)};
  const keep = form.querySelector('[name=usecookie]');
  if (keep) {
    const want = '${widget.keepSeconds}';
    if (keep.tagName === 'SELECT' && ![...keep.options].some(o => o.value === want)) {
      // 选项里没有刚好相同的，选不超过所需时长的最大一项，没有就选最长的
      const opts = [...keep.options].map(o => +o.value).filter(v => v > 0).sort((a, b) => a - b);
      keep.value = String([...opts].reverse().find(v => v <= ${widget.keepSeconds}) ?? opts[opts.length - 1]);
    } else {
      keep.value = want;
    }
  }
  form.submit();
  return true;
})()
''';
    return (await c.evaluateJavascript(source: js)) == true;
  }

  Future<void> _check(InAppWebViewController c, WebUri? uri) async {
    if (_done || uri == null || !uri.host.contains('wenku8')) return;
    final cookies = await _cookieManager.getCookies(url: uri);
    if (cookies.any((e) => e.name == 'jieqiUserInfo') && cookies.any((e) => e.name == 'jieqiVisitInfo')) {
      _done = true;
      if (mounted) Navigator.of(context).pop(cookies.map((e) => '${e.name}=${e.value}').join(';'));
      return;
    }
    if (!_submitted && uri.path.contains('login.php')) _submitted = await _fillAndSubmit(c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录轻小说文库'),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100, minHeight: 2),
              )
            : null,
      ),
      body: !_ready
          ? const SizedBox.shrink()
          : InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.loginUrl)),
              initialSettings: InAppWebViewSettings(userAgent: kUserAgent['User-Agent'], javaScriptEnabled: true),
              onProgressChanged: (_, p) => setState(() => _progress = p),
              onLoadStop: _check,
            ),
    );
  }
}
