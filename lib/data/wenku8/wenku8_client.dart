import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../../models/common/charset_type.dart';
import '../../models/custom_exception.dart';
import 'wenku8_charset.dart';

/// 访问 wenku8 的 HTTP 客户端。
///
/// 只负责"发请求 + 处理编码/重定向/Cloudflare + 管理 cookie"，不依赖 GetX 或本地存储：
/// 节点地址和编码通过构造参数里的函数按需读取，方便测试和以后替换状态管理。
class Wenku8Client {
  Wenku8Client({required this.baseUrl, required this.charset, required Map<String, String> headers, Dio? dio, CookieJar? cookieJar})
    : _cookieJar = cookieJar ?? CookieJar() {
    this.dio = (dio ?? Dio())
      ..options = BaseOptions(headers: headers, responseType: ResponseType.bytes, followRedirects: false, validateStatus: (status) => status != null)
      ..interceptors.add(_CloudflareInterceptor())
      ..interceptors.add(CookieManager(_cookieJar));
  }

  /// 当前节点地址，例如 `https://www.wenku8.net`
  final String Function() baseUrl;

  /// 当前使用的页面编码
  final CharsetType Function() charset;

  final CookieJar _cookieJar;

  late final Dio dio;

  /// 把登录后拿到的 cookie 字符串（`a=1;b=2`）写入 cookie jar，对 [hosts] 里的每个节点都生效。
  Future<void> restoreCookie(String cookie, Iterable<String> hosts) async {
    final cookies = cookie.split(';').map((e) => e.trim()).where((e) => e.contains('=')).map((e) {
      final kv = e.split('=');
      return Cookie(kv[0], kv.sublist(1).join('='));
    }).toList();
    for (final host in hosts) {
      await _cookieJar.saveFromResponse(Uri.parse(host), cookies);
    }
  }

  Future<void> clearCookie() => _cookieJar.deleteAll();

  /// GET 一个页面并按当前编码解码成字符串。
  Future<String> getPage(String url) async {
    final currentCharset = charset();
    final response = await dio.get(Wenku8Charset.withCharsetParam(url, currentCharset));
    final bytes = await _followRedirect(response);
    return Wenku8Charset.decode(bytes, currentCharset);
  }

  /// 以 `application/x-www-form-urlencoded` 提交表单，返回解码后的页面。
  ///
  /// [data] 可以是 Map（由 dio 编码），也可以是已经编码好的字符串。
  Future<String> postForm(String url, Object? data) async {
    final currentCharset = charset();
    final response = await dio.post(
      url,
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    return Wenku8Charset.decode(response.data as Uint8List, currentCharset);
  }

  /// wenku8 会用 3xx 跳转（例如跳到登录页）。dio 关闭了自动跳转，这里手动跟一次，
  /// 好让解析层拿到最终页面并判断出"未登录"等情况。
  Future<Uint8List> _followRedirect(Response response) async {
    final status = response.statusCode;
    if (status != null && status >= 300 && status < 400) {
      final location = response.headers.value('location');
      if (location != null) {
        final target = Uri.parse("${baseUrl()}/").resolve(location);
        final redirected = await dio.getUri(target);
        return redirected.data as Uint8List;
      }
    }
    return response.data as Uint8List;
  }
}

class _CloudflareInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (response.statusCode == 403) {
      handler.reject(Cloudflare403Exception(requestOptions: response.requestOptions));
      return;
    }

    final cfMitigated = response.headers['cf-mitigated'];
    if (cfMitigated != null && cfMitigated.contains('challenge')) {
      handler.reject(CloudflareChallengeException(requestOptions: response.requestOptions));
      return;
    }
    handler.next(response);
  }
}
