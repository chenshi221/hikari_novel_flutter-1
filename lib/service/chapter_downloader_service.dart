import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:get/get.dart' hide Response;
import 'package:html/parser.dart' show parse;
import 'package:hikari_novel_flutter/service/api_service.dart';
import 'package:path_provider/path_provider.dart';

import '../common/log.dart';
import '../models/common/charset_type.dart';
import '../models/common/wenku8_node.dart';

class ChapterDownloaderService extends GetxService {
  final Dio _dio = ApiService.instance.dio;

  // 存储取消令牌：taskId -> CancelToken
  final Map<String, CancelToken> _cancelTokens = {};

  // 存储下载状态：taskId -> bool (true=下载中)
  final Map<String, bool> _downloadingStatus = {};

  /// 取消指定任务的下载
  /// [taskId] 任务唯一标识
  void cancel(String taskId) {
    final token = _cancelTokens[taskId];
    if (token != null && !token.isCancelled) {
      try {
        token.cancel('用户主动取消下载');
        Log.i('任务 $taskId 已取消');
      } catch (e) {
        Log.e('取消任务 $taskId 失败: $e');
      }
    }
  }

  /// 清理指定任务的取消令牌（用于下载完成/失败后）
  void clearCancel(String taskId) {
    _cancelTokens.remove(taskId);
    _downloadingStatus.remove(taskId);
  }

  /// 检查任务是否正在下载
  bool isDownloading(String taskId) => _downloadingStatus[taskId] ?? false;

  /// 检查任务是否已取消
  bool isCanceled(String taskId) {
    final token = _cancelTokens[taskId];
    return token?.isCancelled ?? false;
  }

  /// 下载章节内容并保存到本地
  /// [taskId] 任务唯一标识
  /// [aid] 书籍ID
  /// [cid] 章节ID
  /// [onProgress] 下载进度回调 (已完成字节数, 总字节数)
  Future<String> download({required String taskId, required String aid, required String cid, Function(int received, int total)? onProgress}) async {
    // 检查是否已有相同任务在下载
    if (isDownloading(taskId)) {
      throw Exception('任务 $taskId 正在下载中，请勿重复下载');
    }

    // 检查是否已取消
    if (isCanceled(taskId)) {
      throw Exception('任务 $taskId 已被取消');
    }

    // 标记为下载中
    _downloadingStatus[taskId] = true;

    // 创建取消令牌
    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;

    try {
      // 获取存储目录
      final dir = await getApplicationSupportDirectory();
      final cacheDir = Directory("${dir.path}/cached_chapter");
      if (!(await cacheDir.exists())) {
        await cacheDir.create(recursive: true);
      }
      final savePath = "${cacheDir.path}/${aid}_$cid.txt";

      final charset = switch (ApiService.instance.charsetType) {
        CharsetType.gbk => "gbk",
        CharsetType.big5Hkscs => "big5",
      };
      final url = "${ApiService.instance.wenku8Node.node}/modules/article/reader.php?aid=$aid&cid=$cid&charset=$charset";

      Log.d("$url ${ApiService.instance.charsetType.name}");

      // 发起网络请求获取章节内容
      Response response = await _dio.get(
        url,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          // 进度回调
          if (onProgress != null && total > 0) {
            onProgress(received, total);
          }
        },
      );

      // 共享的Dio不跟随重定向，这里和ApiService一样手动跟随一次
      final location = response.headers.value('location');
      if (response.statusCode != null && response.statusCode! >= 300 && response.statusCode! < 400 && location != null) {
        response = await _dio.get("${ApiService.instance.wenku8Node.node}/$location", cancelToken: cancelToken);
      }

      // 检查是否在请求过程中被取消
      if (cancelToken.isCancelled) {
        throw DioException(requestOptions: response.requestOptions, type: DioExceptionType.cancel, message: '任务 $taskId 下载过程中被取消');
      }

      // 共享的Dio接受任何状态码，非200的错误页不能写进缓存，否则阅读器会一直读到它
      if (response.statusCode != 200) {
        throw Exception('任务 $taskId 下载失败: HTTP ${response.statusCode}');
      }

      // 解码
      String content;
      switch (ApiService.instance.charsetType) {
        case CharsetType.gbk:
          {
            content = GbkCodec().decode(response.data as Uint8List);
          }
        case CharsetType.big5Hkscs:
          {
            content = Big5Codec().decode(response.data as Uint8List);
          }
      }

      // 不是章节页面（如登录页、提示页）时不缓存
      if (parse(content).getElementById('content') == null) {
        throw Exception('任务 $taskId 下载失败: 返回的不是章节内容');
      }

      // 写入文件（覆盖原有文件）
      final file = File(savePath);
      await file.writeAsString(content, flush: true);

      Log.i('章节 $aid-$cid 下载完成，保存路径：$savePath');
      return savePath;
    } on DioException catch (e) {
      // 处理Dio异常（重点处理取消类型）
      if (e.type == DioExceptionType.cancel) {
        Log.e('任务 $taskId 被取消: ${e.message}');
        throw Exception('canceled');
      } else {
        Log.e('任务 $taskId 下载失败: ${e.message}');
        rethrow;
      }
    } catch (e) {
      // 处理其他异常
      Log.e('任务 $taskId 处理失败: $e');
      rethrow;
    } finally {
      // 无论成功/失败/取消，都清理状态
      _downloadingStatus.remove(taskId);
      _cancelTokens.remove(taskId);
    }
  }

  /// 取消所有正在进行的下载任务
  void cancelAll() {
    _cancelTokens.keys.forEach(cancel);
    _cancelTokens.clear();
    _downloadingStatus.clear();
  }

  /// 清理所有取消令牌和状态
  void dispose() {
    cancelAll();
  }
}
