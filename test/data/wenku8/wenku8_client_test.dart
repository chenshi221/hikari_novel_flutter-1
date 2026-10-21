import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_client.dart';
import 'package:hikari_novel_flutter/models/common/charset_type.dart';
import 'package:hikari_novel_flutter/models/custom_exception.dart';

/// 按请求路径返回预设响应的假适配器，并记录请求过的地址
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.routes);

  final Map<String, ResponseBody Function()> routes;
  final List<Uri> requested = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requested.add(options.uri);
    return routes[options.uri.path]!();
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _redirect(String location) => ResponseBody.fromBytes(
  const [],
  302,
  headers: {
    'location': [location],
  },
);

ResponseBody _page(List<int> bytes) => ResponseBody.fromBytes(bytes, 200);

Wenku8Client _client(_FakeAdapter adapter) =>
    Wenku8Client(baseUrl: () => 'https://www.wenku8.net', charset: () => CharsetType.gbk, headers: const {}, dio: Dio()..httpClientAdapter = adapter);

void main() {
  test('跟随多次重定向（相对、以 / 开头、绝对地址），并按 GBK 解码最终页面', () async {
    final adapter = _FakeAdapter({
      '/a.php': () => _redirect('b.php'),
      '/b.php': () => _redirect('/c.php'),
      '/c.php': () => _redirect('https://www.wenku8.net/login.php'),
      '/login.php': () => _page([0xB5, 0xC7, 0xC2, 0xBC]), // "登录"
    });

    final html = await _client(adapter).getPage('https://www.wenku8.net/a.php');

    expect(html, '登录');
    expect(adapter.requested.map((u) => u.path), ['/a.php', '/b.php', '/c.php', '/login.php']);
    expect(adapter.requested.first.query, '&charset=gbk');
  });

  test('重定向死循环时最多跟随 5 次', () async {
    final adapter = _FakeAdapter({'/loop.php': () => _redirect('loop.php')});
    await expectLater(_client(adapter).getPage('https://www.wenku8.net/loop.php'), completes);
    expect(adapter.requested, hasLength(6));
  });

  test('403 识别为 Cloudflare 拦截', () async {
    final adapter = _FakeAdapter({'/x.php': () => ResponseBody.fromBytes(const [], 403)});
    await expectLater(_client(adapter).getPage('https://www.wenku8.net/x.php'), throwsA(isA<Cloudflare403Exception>()));
  });

  test('恢复 cookie 时值里带逗号也不会报错', () async {
    final client = _client(_FakeAdapter({}));
    await client.restoreCookie('jieqiUserInfo=abc;jieqiRecentRead=1792527353,1792527401,1792527434', ['https://www.wenku8.net']);
  });
}
