import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/wenku8/wenku8_txt.dart';
import 'session.dart';

/// 下载 TXT 失败（网络、HTTP 状态不对、拿到空文件）。
class TxtDownloadException implements Exception {
  const TxtDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 从 dl.wenku8.com 下载全本 TXT。下载站不检查登录，受限 / 下架的书也能拿到。
class TxtDownloader {
  TxtDownloader(this._dio);

  final Dio _dio;

  /// 拉全书字节。[type] 是下载类型（txt / utf8 / big5），[node] 是下载节点。
  Future<Uint8List> fetch(String aid, {required String type, int node = 1}) async {
    final url = Wenku8Txt.fullBookUrl(aid, type: type, node: node);
    final Response<List<int>> response;
    try {
      response = await _dio.get<List<int>>(url, options: Options(validateStatus: (_) => true));
    } on DioException catch (e) {
      throw TxtDownloadException('连接下载服务器失败（${e.type.name}）');
    }
    final status = response.statusCode;
    if (status != 200) throw TxtDownloadException('下载服务器返回 HTTP $status');
    final data = response.data;
    if (data == null || data.isEmpty) throw const TxtDownloadException('下载到的 TXT 是空的');
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  /// 保存到临时目录，文件名为 `<书名>.txt`（书名里的非法字符已处理）。分享 / 用其他阅读器打开用。
  Future<File> saveToTemp(Uint8List bytes, String title) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${Wenku8Txt.sanitizeFileName(title)}.txt'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 下载并保存，返回临时文件。
  Future<File> download({required String aid, required String title, required String type, int node = 1}) async {
    final bytes = await fetch(aid, type: type, node: node);
    return saveToTemp(bytes, title);
  }
}

final txtDownloaderProvider = Provider<TxtDownloader>((ref) {
  final store = ref.watch(sessionStoreProvider);
  final dio = Dio(
    BaseOptions(
      responseType: ResponseType.bytes,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 120),
      headers: {'User-Agent': store.userAgent, 'Accept': '*/*'},
    ),
  )..httpClientAdapter = store.adapter();
  return TxtDownloader(dio);
});
