import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../common/constants.dart';

/// 原生 App 的登录网页。登录成功（拿到 jieqiUserInfo 和 jieqiVisitInfo 两个 cookie）后
/// 关闭页面，并把 cookie 字符串返回给登录页。
class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key, required this.loginUrl});

  final String loginUrl;

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  final _cookieManager = CookieManager.instance();
  bool _ready = false;
  bool _done = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    // 先清掉旧 cookie，避免直接带着过期的登录状态进入
    _cookieManager.deleteAllCookies().whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  Future<void> _check(WebUri? uri) async {
    if (_done || uri == null || !uri.host.contains('wenku8')) return;
    final cookies = await _cookieManager.getCookies(url: uri);
    String? value(String name) => cookies.where((c) => c.name == name).map((c) => c.value.toString()).firstOrNull;
    final info = value('jieqiUserInfo');
    final visit = value('jieqiVisitInfo');
    if (info == null || visit == null || !mounted) return;
    _done = true;
    Navigator.of(context).pop('jieqiUserInfo=$info;jieqiVisitInfo=$visit');
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
              onLoadStop: (_, uri) => _check(uri),
            ),
    );
  }
}
