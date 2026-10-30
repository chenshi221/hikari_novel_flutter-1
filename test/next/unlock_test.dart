import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_app_api.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_client.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_parser.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_urls.dart';
import 'package:hikari_novel_flutter/models/common/charset_type.dart';
import 'package:hikari_novel_flutter/models/cat_chapter.dart';
import 'package:hikari_novel_flutter/models/cat_volume.dart';
import 'package:hikari_novel_flutter/models/content.dart';
import 'package:hikari_novel_flutter/next/cache.dart';
import 'package:hikari_novel_flutter/next/data.dart';
import 'package:hikari_novel_flutter/next/read_state.dart';
import 'package:hikari_novel_flutter/next/txt_download.dart';
import 'package:hikari_novel_flutter/next/unlock.dart';
import 'package:hive_ce/hive.dart';

/// 假的 App 接口：可以设置成"接口挂了"或者返回一份目录。
class _FakeApi implements Wenku8AppApi {
  _FakeApi({this.volumes, this.fail = false});

  final List<CatVolume>? volumes;
  final bool fail;
  int calls = 0;

  @override
  Future<List<CatVolume>> catalogue(String aid) async {
    calls++;
    if (fail || volumes == null) throw const Wenku8AppApiException('接口不可用');
    return volumes!;
  }

  @override
  Future<Content> chapter(String aid, String cid) async {
    if (fail) throw const Wenku8AppApiException('接口不可用');
    return Content(text: '接口正文 $cid', images: const []);
  }

  @override
  Future<Wenku8NovelDetail?> meta(String aid) async => null;
}

/// 假的 TXT 下载器：把测试样本按 GBK 原地返回，不联网。
class _FakeTxt implements TxtDownloader {
  _FakeTxt(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> fetch(String aid, {required String type, int node = 1}) async => bytes;

  @override
  Future<File> saveToTemp(Uint8List bytes, String title) async => File('${Directory.systemTemp.path}/$title.txt');

  @override
  Future<File> download({required String aid, required String title, required String type, int node = 1}) async => saveToTemp(bytes, title);
}

/// 网站：要么回一个页面（GBK），要么断网。
class _Site implements HttpClientAdapter {
  _Site({this.html, this.offline = false});

  final String? html;
  final bool offline;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (offline) throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    return ResponseBody.fromBytes(const GbkCodec(allowInvalid: true).encode(html!), 200);
  }

  @override
  void close({bool force = false}) {}
}

/// 用真实 OVERLORD TXT 片段（fixture）造一份 GBK 字节，模拟 dl.wenku8.com 的 response。
Uint8List _fixtureBytes() {
  final text = File('test/data/wenku8/fixtures/txt_book.txt').readAsStringSync();
  return Uint8List.fromList(const GbkCodec(allowInvalid: true).encode(text));
}

void main() {
  final bytes = _fixtureBytes();

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('hikari_unlock_test').path);
    await Hive.openBox('session');
    await ChapterCache.open();
  });

  setUp(() async {
    await Hive.box('session').clear();
    // 书籍解锁默认关闭、入口默认隐藏；单测里直接打开功能开关
    await Hive.box('session').put('p.unlock.enabled', true);
  });

  ProviderContainer container({Wenku8AppApi? api}) => ProviderContainer(
    overrides: [
      appApiProvider.overrideWithValue(api ?? _FakeApi(fail: true)),
      txtDownloaderProvider.overrideWithValue(_FakeTxt(bytes)),
    ],
  );

  test('TXT 回退：接口不可用时解析全本，写章节缓存 + 目录，并标成离线缓存', () async {
    final c = container();
    addTearDown(c.dispose);
    final report = await c.read(unlockServiceProvider).unlock('1592', 'OVERLORD不死者之王');

    expect(report.source, 'txt');
    expect(report.chapters, greaterThan(0));

    final catalogue = UnlockStore.catalogue('1592');
    expect(catalogue, isNotNull);
    expect(catalogue!.length, greaterThanOrEqualTo(2)); // 样本里有第一、二卷
    final cids = catalogue.expand((v) => v.chapters).map((c) => c.cid).toList();
    expect(cids, hasLength(report.chapters));
    expect(cids.first, 'u1');

    // 每章正文都写进了离线缓存
    for (final cid in cids) {
      final content = await ChapterCache.get('1592', cid);
      expect(content, isNotNull, reason: '章 $cid 没有正文');
      expect(content!.text, isNotEmpty);
    }

    expect(UnlockStore.source('1592'), 'txt');
    expect(UnlockStore.title('1592'), 'OVERLORD不死者之王');
    expect(ChapterCache.offline('1592'), isTrue, reason: '解锁的书应记为离线缓存，自动清理时不会被删');
  });

  test('API 优先：接口可用时只存 App 接口目录，正文按需再取', () async {
    final volumes = [
      CatVolume(title: '第一卷 测试', chapters: [CatChapter(title: '第一章', cid: '123'), CatChapter(title: '第二章', cid: '124')]),
    ];
    final c = container(api: _FakeApi(volumes: volumes));
    addTearDown(c.dispose);
    final report = await c.read(unlockServiceProvider).unlock('42', '测试书');

    expect(report.source, 'api');
    expect(report.chapters, 2);
    expect(UnlockStore.catalogue('42')!.first.chapters.map((c) => c.cid), ['123', '124']);
    // 正文没有预先缓存（读的时候会走 App 接口）
    expect(ChapterCache.has('42', '123'), isFalse);
  });

  test('两条路都失败：抛 UnlockException，消息里带两边原因，且不留下目录', () async {
    final c = ProviderContainer(
      overrides: [
        appApiProvider.overrideWithValue(_FakeApi(fail: true)),
        txtDownloaderProvider.overrideWithValue(_FakeTxt(Uint8List.fromList(const GbkCodec().encode('不是 TXT'))))
      ],
    );
    addTearDown(c.dispose);
    await expectLater(c.read(unlockServiceProvider).unlock('77', '坏书'), throwsA(isA<UnlockException>()));
    expect(UnlockStore.has('77'), isFalse);
  });

  group('Api 什么时候走解锁', () {
    const base = 'https://www.wenku8.net';
    final volumes = [
      CatVolume(title: '接口卷', chapters: [CatChapter(title: '第一章', cid: '123')]),
    ];

    Api api(ProviderContainer c, _Site site, {String scope = 'u1'}) {
      final client = Wenku8Client(baseUrl: () => base, charset: () => CharsetType.gbk, headers: const {}, dio: Dio()..httpClientAdapter = site);
      return Api(client, Wenku8Urls(base, CharsetType.gbk), base, scope, unlock: c.read(unlockServiceProvider));
    }

    test('TXT 解锁过的书只用存下的目录，App 接口能用也不换', () async {
      final c = container();
      addTearDown(c.dispose);
      await c.read(unlockServiceProvider).unlock('1592', 'OVERLORD');
      final fake = _FakeApi(volumes: volumes);
      final c2 = ProviderContainer(overrides: [appApiProvider.overrideWithValue(fake)]);
      addTearDown(c2.dispose);

      final cat = await api(c2, _Site(html: '<html><body>无目录</body></html>')).catalogue('1592');
      expect(cat.first.chapters.first.cid, 'u1');
      expect(fake.calls, 0);
    });

    test('断网、游客都不走解锁，照原样报错', () async {
      final fake = _FakeApi(volumes: volumes);
      final c = ProviderContainer(overrides: [appApiProvider.overrideWithValue(fake)]);
      addTearDown(c.dispose);

      await expectLater(api(c, _Site(offline: true)).catalogue('5'), throwsA(isA<DioException>()));
      await expectLater(api(c, _Site(html: '<html>请登录</html>'), scope: 'guest').novel('5'), throwsA(anything));
      expect(fake.calls, 0);
      // 登录了、网站不给目录：才去问 App 接口
      expect((await api(c, _Site(html: '<html>无目录</html>')).catalogue('5')).first.chapters.first.cid, '123');
      expect(fake.calls, 1);
    });
  });

  test('清除已读章节跳过 TXT 解锁的书（正文删了补不回来）', () async {
    final c = container();
    addTearDown(c.dispose);
    await c.read(unlockServiceProvider).unlock('66', '书');
    await ReadState.setRead('66', ['u1'], true);
    await ChapterCache.clearRead();
    expect(ChapterCache.has('66', 'u1'), isTrue);
  });

  test('forget 只清目录，不删已经缓存的正文', () async {
    final c = container();
    addTearDown(c.dispose);
    await c.read(unlockServiceProvider).unlock('88', '书');
    final cid = UnlockStore.catalogue('88')!.first.chapters.first.cid;
    await c.read(unlockServiceProvider).forget('88');

    expect(UnlockStore.has('88'), isFalse);
    expect(UnlockStore.catalogue('88'), isNull);
    expect(ChapterCache.has('88', cid), isTrue);
  });
}
