import 'package:dio/dio.dart';

/// 网页预览没有系统网络栈。
HttpClientAdapter? nativeAdapter(HttpClientAdapter Function() fallback) => null;
