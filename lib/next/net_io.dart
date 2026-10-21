import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

/// 用系统自带的网络栈发请求：安卓是 Cronet（和 Chrome 同一套 TLS），苹果是 NSURLSession（和 Safari / WebView 同一套）。
/// Dart 自己的 TLS 指纹和浏览器不一样，Cloudflare 会据此拦截；WebView 通过验证后拿到的 cf_clearance，用同样指纹的请求才不容易被再次质询。
///
/// - 安卓设备没有 Google 服务、Cronet 不可用时退回 [fallback]（Dart 自己的网络层）
/// - 苹果端关掉系统的 cookie 处理：cookie 由 Dio 的 cookie jar 自己管，免得两边各发一份
HttpClientAdapter? nativeAdapter(HttpClientAdapter Function() fallback) {
  if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return null;
  return NativeAdapter(
    createFallbackAdapter: (_, _) => fallback(),
    createCupertinoConfiguration: () => URLSessionConfiguration.ephemeralSessionConfiguration()
      ..httpShouldSetCookies = false
      ..httpCookieAcceptPolicy = NSHTTPCookieAcceptPolicy.NSHTTPCookieAcceptPolicyNever,
  );
}
