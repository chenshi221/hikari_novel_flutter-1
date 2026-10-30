import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../data/wenku8/wenku8_app_api.dart';
import '../data/wenku8/wenku8_parser.dart';
import '../data/wenku8/wenku8_txt.dart';
import '../models/cat_chapter.dart';
import '../models/cat_volume.dart';
import '../models/content.dart';
import 'app_prefs.dart';
import 'cache.dart';
import 'session.dart';
import 'txt_download.dart';

/// 解锁失败：App 接口和 TXT 两条路都走不通时抛出，[message] 里带上各自的原因。
class UnlockException implements Exception {
  const UnlockException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次解锁的结果。
class UnlockReport {
  const UnlockReport(this.source, this.chapters);

  /// 正文来源：`api` = 文库 App 接口，`txt` = dl.wenku8.com 全本 TXT
  final String source;

  /// 解锁后的章节数
  final int chapters;
}

/// 解锁过的书的目录，存在 Hive 的 `session` 里：
/// - `unlock:vols:<aid>`：卷列表 `[{t, c: [{c, t}]}]`（卷名、章节 cid/章名）
/// - `unlock:meta:<aid>`：`{title, source, time}`（书名、解锁来源、解锁时间）
///
/// 正文不在这里，走 [ChapterCache]（和离线缓存同一套 `aid:cid`）。当前解锁记录、设置页
/// 需要判断"这本书解锁过没有"时直接调这里的静态方法。
class UnlockStore {
  UnlockStore._();

  static Box get _box => Hive.box('session');

  static String _volsKey(String aid) => 'unlock:vols:$aid';

  static String _metaKey(String aid) => 'unlock:meta:$aid';

  static Map? _meta(String aid) => _box.get(_metaKey(aid)) as Map?;

  /// 读回解锁时存下的目录；没解锁过或数据坏了返回 null。
  static List<CatVolume>? catalogue(String aid) {
    final raw = _box.get(_volsKey(aid));
    if (raw is! List) return null;
    final volumes = <CatVolume>[];
    for (final v in raw) {
      if (v is! Map) continue;
      final chaptersRaw = v['c'];
      if (chaptersRaw is! List) continue;
      final chapters = <CatChapter>[];
      for (final c in chaptersRaw) {
        if (c is! Map) continue;
        final cid = c['c'];
        final title = c['t'];
        if (cid is String && title is String) chapters.add(CatChapter(title: title, cid: cid));
      }
      final title = v['t'];
      volumes.add(CatVolume(title: title is String ? title : '', chapters: chapters));
    }
    return volumes.isEmpty ? null : volumes;
  }

  static bool has(String aid) => _box.containsKey(_volsKey(aid));

  /// 存目录和元信息。正文由调用方（[UnlockService]）写 [ChapterCache]。
  static Future<void> save(String aid, String title, List<CatVolume> volumes, {required String source}) async {
    await _box.put(_volsKey(aid), [
      for (final v in volumes)
        {
          't': v.title,
          'c': [
            for (final c in v.chapters) {'c': c.cid, 't': c.title},
          ],
        },
    ]);
    await _box.put(_metaKey(aid), {'title': title, 'source': source, 'time': DateTime.now().millisecondsSinceEpoch});
  }

  /// 只删目录，不删已经写进 [ChapterCache] 的正文。
  static Future<void> forget(String aid) => _box.deleteAll([_volsKey(aid), _metaKey(aid)]);

  static String? source(String aid) => _meta(aid)?['source'] as String?;

  /// 解锁时间（毫秒时间戳）
  static int? time(String aid) => _meta(aid)?['time'] as int?;

  static String? title(String aid) => _meta(aid)?['title'] as String?;

  /// 所有解锁过的书号
  static Iterable<String> aids() => _box.keys.whereType<String>().where((k) => k.startsWith('unlock:vols:')).map((k) => k.substring('unlock:vols:'.length));
}

/// 解锁编排：优先文库 App 接口（有真正的 cid，图片也能取），失败自动回退到
/// dl.wenku8.com 的全本 TXT（解析成同样的卷/章，正文写进本地章节缓存）。
///
/// 网页拒绝提供目录 / 正文时，[Api] 会来问这里；界面上的"解锁本书"也调这里。
class UnlockService {
  UnlockService(this._ref);

  final Ref _ref;

  /// 书籍解锁总开关（默认开）
  bool get enabled => AppPrefs.read(P.unlock, false);

  bool get _apiEnabled => AppPrefs.read(P.unlockApi, true);

  String get _type => AppPrefs.read(P.unlockType, 'txt');

  int get _node => AppPrefs.read(P.unlockNode, 1);

  /// 解锁时存下的目录（不联网）
  Future<List<CatVolume>?> storedCatalogue(String aid) async => UnlockStore.catalogue(aid);

  /// App 接口的目录；没开 App 接口或失败返回 null。
  Future<List<CatVolume>?> apiCatalogue(String aid) async {
    if (!enabled || !_apiEnabled) return null;
    try {
      final volumes = await _ref.read(appApiProvider).catalogue(aid);
      return volumes.isEmpty ? null : volumes;
    } catch (_) {
      return null;
    }
  }

  /// App 接口的正文；没开 App 接口或失败返回 null。
  Future<Content?> apiChapter(String aid, String cid) async {
    if (!enabled || !_apiEnabled) return null;
    try {
      return await _ref.read(appApiProvider).chapter(aid, cid);
    } catch (_) {
      return null;
    }
  }

  /// App 接口的书籍信息（下架书的详情页兜底）；失败返回 null。
  Future<Wenku8NovelDetail?> apiDetail(String aid) async {
    if (!enabled || !_apiEnabled) return null;
    try {
      return await _ref.read(appApiProvider).meta(aid);
    } catch (_) {
      return null;
    }
  }

  /// 解锁一本书：先试 App 接口，失败再下载全本 TXT 解析、写章节缓存、存目录。
  /// 两条路都失败时抛 [UnlockException]，消息里带各自的原因。
  Future<UnlockReport> unlock(String aid, String title) async {
    if (!enabled) throw const UnlockException('书籍解锁未开启');
    final errors = <String>[];

    if (_apiEnabled) {
      try {
        final api = _ref.read(appApiProvider);
        final volumes = await api.catalogue(aid);
        final first = volumes.expand((v) => v.chapters).firstOrNull;
        if (first == null) throw const UnlockException('App 接口没有返回章节');
        // 目录可能对、正文接口却挂了：先取第一章确认真的能读，再存目录
        await api.chapter(aid, first.cid);
        await UnlockStore.save(aid, title, volumes, source: 'api');
        return UnlockReport('api', volumes.fold(0, (n, v) => n + v.chapters.length));
      } catch (e) {
        errors.add('App 接口：${_brief(e)}');
      }
    }

    final written = <String>[];
    try {
      final bytes = await _ref.read(txtDownloaderProvider).fetch(aid, type: _type, node: _node);
      final book = Wenku8Txt.parse(Wenku8Txt.decodeBytes(bytes, _type), aid: aid, fallbackTitle: title);
      for (final volume in book.volumes) {
        for (final chapter in volume.chapters) {
          final body = book.texts[chapter.cid];
          if (body == null || body.isEmpty) continue;
          await ChapterCache.put(aid, chapter.cid, Content(text: body, images: const []));
          written.add(chapter.cid);
        }
      }
      if (written.isEmpty) throw const UnlockException('TXT 里没有可读的正文');
      await UnlockStore.save(aid, book.title, book.volumes, source: 'txt');
      // 记为「离线缓存」：启动时的自动清理不会把这些 TXT 正文删掉，存储页也能看到
      final first = book.volumes.expand((v) => v.chapters).firstOrNull;
      await ChapterCache.setMeta(aid, book.title, written.length, '', first?.cid ?? '');
      return UnlockReport('txt', written.length);
    } catch (e) {
      // 中途失败：把已经写进去的半本书清掉，别留下"有正文没目录"的状态
      if (written.isNotEmpty) await ChapterCache.removeChapters(aid, written);
      errors.add('TXT：${_brief(e)}');
    }

    throw UnlockException(errors.join('；'));
  }

  /// 只下载 TXT 文件（不解锁、不写章节缓存），供界面分享。
  Future<File> downloadTxt(String aid, String title, {String? type, int? node}) =>
      _ref.read(txtDownloaderProvider).download(aid: aid, title: title, type: type ?? _type, node: node ?? _node);

  /// 删掉解锁记录（不删章节缓存）。
  Future<void> forget(String aid) => UnlockStore.forget(aid);

  static String _brief(Object e) {
    final message = switch (e) {
      Wenku8AppApiException() => e.message,
      TxtDownloadException() => e.message,
      UnlockException() => e.message,
      FormatException() => e.message,
      _ => e.toString(),
    };
    final text = message.toString();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }
}

final appApiProvider = Provider<Wenku8AppApi>((ref) {
  final store = ref.watch(sessionStoreProvider);
  final dio = Dio(BaseOptions(responseType: ResponseType.bytes, connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 30)))
    ..httpClientAdapter = store.adapter();
  return Wenku8AppApi(dio: dio);
});

final unlockServiceProvider = Provider<UnlockService>((ref) => UnlockService(ref));
