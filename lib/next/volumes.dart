import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/cat_volume.dart';
import 'cache.dart';
import 'data.dart';
import 'image_cache.dart';
import 'progress.dart';
import 'read_state.dart';
import 'stats.dart';

/// 目录里的一卷：卷名、章节 cid（按顺序）、插图章节的 cid（没有为 null）。
class Vol {
  const Vol(this.title, this.cids, this.illus);

  factory Vol.from(CatVolume v) => Vol(v.title, [for (final c in v.chapters) c.cid], v.chapters.where((c) => isIllustration(c.title)).firstOrNull?.cid);

  final String title;
  final List<String> cids;
  final String? illus;

  /// 判断读完用的章节：不算插图章（只有图，很多人会跳过）
  Iterable<String> get textCids => cids.where((c) => c != illus);
}

bool isIllustration(String title) => title.contains('插图') || title.contains('插圖') || title.contains('插画') || title.contains('插畫');

/// 分卷数据，全部存在本机（不用每次都请求网页）：
/// - `vols:aid` 卷列表（目录加载时记下，书架、报告页同步就能用）
/// - `vcover2:aid` 卷名 → 封面地址（插图章节里第一张竖着的图，见 [chooseCover]；'' 表示这卷没有插图）
///   （`vcover:` 是旧版直接取第一张图的记录，作废不用）
/// - `vdone:aid` 卷名 → 读完的时间（毫秒）
/// - `vrate:aid` 卷名 → 星级
class Volumes {
  Volumes._();

  static Box get _box => Hive.box('session');

  /// 卷封面、读完状态变了：书架、书籍墙、报告页据此刷新
  static final changes = ValueNotifier<int>(0);

  static List<Vol> of(String aid) => [
    for (final m in ((_box.get('vols:$aid') as List?) ?? const []).cast<Map>()) Vol(m['t'] as String, (m['c'] as List).cast<String>(), m['i'] as String?),
  ];

  /// 目录加载后记下卷列表，并顺带核对一遍哪些卷读完了。
  static Future<void> saveCatalogue(String aid, List<CatVolume> cat) async {
    final next = [
      for (final v in cat)
        {'t': v.title, 'c': [for (final c in v.chapters) c.cid], 'i': v.chapters.where((c) => isIllustration(c.title)).firstOrNull?.cid},
    ];
    if (!listEquals(next.map((e) => '${e['t']}|${(e['c'] as List).length}').toList(), of(aid).map((v) => '${v.title}|${v.cids.length}').toList())) {
      await _box.put('vols:$aid', next);
    }
    await refreshDone(aid);
  }

  /// [cid] 在第几卷，找不到为 -1。
  static int indexOf(String aid, String cid) => of(aid).indexWhere((v) => v.cids.contains(cid));

  // ---- 封面 ----

  static Map<String, String> _covers(String aid) => ((_box.get('vcover2:$aid') as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as String));

  /// 这卷的封面：null 还没取过，'' 这卷没有插图。
  static String? cover(String aid, String title) => _covers(aid)[title];

  /// [url] 可以带裁剪框（见 [withCrop]），自选封面就是这样存的
  static Future<void> setCover(String aid, String title, String url) async {
    await _box.put('vcover2:$aid', {..._covers(aid), title: url});
    changes.value++;
  }

  /// 忘掉这本书所有卷的封面记录（没加入书架的书退出详情页时）
  static Future<void> forgetCovers(String aid) async {
    await _box.delete('vcover2:$aid');
    changes.value++;
  }

  /// 去掉自选的封面，下次显示时重新自动挑
  static Future<void> resetCover(String aid, String title) async {
    await _box.put('vcover2:$aid', {..._covers(aid)}..remove(title));
    changes.value++;
  }

  /// 图片缓存清理时要留着的封面
  static Iterable<String> allCovers() => _box.keys.whereType<String>().where((k) => k.startsWith('vcover2:')).expand((k) => (_box.get(k) as Map).values.cast<String>()).where((e) => e.isNotEmpty);

  // ---- 读完 ----

  static Map<String, int> done(String aid) => ((_box.get('vdone:$aid') as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as int));

  /// 按已读章节核对每卷：正文章节全读了就记下读完时间，不再全读（标回未读）就去掉。
  /// 第一次核对这本书时（以前读完的卷没有日期），用最后一次阅读的时间代替。
  static Future<void> refreshDone(String aid) async {
    final vols = of(aid);
    if (vols.isEmpty) return;
    final first = !_box.containsKey('vdone:$aid');
    final last = ReadingProgress.lastRead(aid);
    final now = first && last > 0 ? last : DateTime.now().millisecondsSinceEpoch;
    final read = ReadState.read(aid);
    final old = done(aid);
    final next = <String, int>{
      for (final v in vols)
        if (v.textCids.isNotEmpty && v.textCids.every(read.contains)) v.title: old[v.title] ?? now,
    };
    if (first || !mapEquals(old, next)) {
      await _box.put('vdone:$aid', next);
      changes.value++;
    }
  }

  /// 所有读完的卷：(aid, 卷序号, 卷, 读完时间)，新的在前。书籍墙用。
  static List<(String, int, Vol, int)> allDone() {
    final out = <(String, int, Vol, int)>[];
    for (final k in _box.keys.whereType<String>().where((k) => k.startsWith('vdone:'))) {
      final aid = k.substring(6);
      final vols = of(aid);
      for (final e in done(aid).entries) {
        final i = vols.indexWhere((v) => v.title == e.key);
        if (i >= 0) out.add((aid, i, vols[i], e.value));
      }
    }
    return out..sort((a, b) => b.$4.compareTo(a.$4));
  }

  // ---- 评分 ----

  static int rating(String aid, String title) => ((_box.get('vrate:$aid') as Map?)?[title] as int?) ?? 0;

  static Future<void> setRating(String aid, String title, int stars) => _box.put('vrate:$aid', {...((_box.get('vrate:$aid') as Map?) ?? const {}), title: stars});

  // ---- 统计 ----

  /// 这卷读了多少秒、哪些天读过（按章记录的时间，这个功能上线之后才有）。
  static ({int seconds, List<String> days}) time(String aid, Vol v) {
    final ch = ReadingStats.chapterSeconds(aid);
    var seconds = 0;
    final days = <String>{};
    for (final c in v.cids) {
      for (final e in (ch[c] ?? const <String, int>{}).entries) {
        seconds += e.value;
        days.add(e.key);
      }
    }
    return (seconds: seconds, days: days.toList()..sort());
  }

  /// 这卷读过的字数：读过、而且缓存过（读过的章节都会自动缓存）的章节字数之和。
  static int readChars(String aid, Vol v) {
    final read = ReadState.read(aid);
    return v.cids.where(read.contains).fold(0, (a, c) => a + (ChapterCache.length(aid, c) ?? 0));
  }
}

/// 取卷封面：一次只取一卷，新请求的先取（刚滑到眼前的），从网上取的之间隔一会儿，免得被限流。
/// 插图章节缓存过就直接用缓存，不联网；从网上取到的正文也顺手存进缓存。网络出问题就先停下，下次再说。
class VolumeCoverQueue {
  VolumeCoverQueue(this._ref);

  final Ref _ref;
  final _queue = <(String, String)>[];
  final _bg = <(String, String)>[]; // 后台慢慢取的，排在眼前要看的后面
  bool _running = false;

  /// 后台把这些书所有卷的封面都取下来（打开 App、同步完书架后调用），不用等翻到才取。
  void prefetchAll(Iterable<String> aids) {
    for (final aid in aids) {
      for (final v in Volumes.of(aid)) {
        if (Volumes.cover(aid, v.title) == null && !_bg.contains((aid, v.title))) _bg.add((aid, v.title));
      }
    }
    Future.microtask(_pump);
  }

  /// 没加入书架的书退出详情页时：不再取它的封面，删掉挑封面时下载的图（插图章节的前几张）和封面记录，下次打开再取。
  Future<void> forget(String aid) async {
    _queue.removeWhere((e) => e.$1 == aid);
    _bg.removeWhere((e) => e.$1 == aid);
    final store = _ref.read(imageStoreProvider);
    for (final v in Volumes.of(aid)) {
      if (v.illus == null || Volumes.cover(aid, v.title) == null) continue;
      final content = await ChapterCache.get(aid, v.illus!);
      if (content != null) await store.remove(content.images.take(_checked));
    }
    await Volumes.forgetCovers(aid);
  }

  /// 一卷的封面；这卷没有插图（比如短篇集）或者还没取到时用书的高清封面（第一卷的）。
  String volCover(String aid, Vol v, String fallback) => get(aid, v) ?? bookCover(aid, fallback);

  /// 这卷的封面，还没取过就排队去取（返回 null）；没有插图也返回 null。
  String? get(String aid, Vol v) {
    final url = Volumes.cover(aid, v.title);
    if (url == null && !_queue.contains((aid, v.title))) {
      _queue.add((aid, v.title));
      Future.microtask(_pump);
    }
    return url == null || url.isEmpty ? null : url;
  }

  /// 书的封面：第一卷的卷封面（高清）；没有卷信息、还没取到、没插图时用 [fallback]（网站的小封面）。
  String bookCover(String aid, String fallback) {
    final vols = Volumes.of(aid);
    return vols.isEmpty ? fallback : get(aid, vols.first) ?? fallback;
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty || _bg.isNotEmpty) {
        final (aid, title) = _queue.isNotEmpty ? _queue.removeLast() : _bg.removeAt(0);
        final v = Volumes.of(aid).where((v) => v.title == title).firstOrNull;
        if (v == null || Volumes.cover(aid, title) != null) continue;
        if (v.illus == null) {
          await Volumes.setCover(aid, title, '');
          continue;
        }
        var content = await ChapterCache.get(aid, v.illus!);
        if (content == null) {
          try {
            content = await _ref.read(apiProvider).chapter(aid, v.illus!);
          } catch (_) {
            _queue.clear();
            _bg.clear(); // 网络出问题就先停，下次打开 App 再接着取
            return;
          }
          await ChapterCache.put(aid, v.illus!, content);
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }
        final String url;
        try {
          url = await chooseCover(content.images, _size);
        } catch (_) {
          _queue.clear(); // 图片下不下来，多半是网络问题，下次再说
          _bg.clear();
          return;
        }
        await Volumes.setCover(aid, title, url);
        await _dropSkipped(aid, v, content.images);
      }
    } finally {
      _running = false;
    }
  }

  /// 挑封面时下载了又没选上的图（插图章节开头的横版跨页，一张几百 KB）删掉，只留封面；以后打开插图章节再下。
  /// 下载过离线缓存的书不删，离线时还要看。
  Future<void> _dropSkipped(String aid, Vol v, List<String> images) async {
    if (ChapterCache.offline(aid)) return;
    final cover = splitCrop(Volumes.cover(aid, v.title) ?? '').url;
    await _ref.read(imageStoreProvider).remove(images.take(_checked).where((u) => u != cover));
  }

  /// 以前挑封面时留下的这种图删一遍（只做一次）
  Future<void> dropSkippedOnce(Iterable<String> aids) async {
    final box = Hive.box('session');
    if (box.get('coverSkipDropped') == true) return;
    for (final aid in aids) {
      for (final v in Volumes.of(aid)) {
        if (v.illus == null || Volumes.cover(aid, v.title) == null) continue;
        final content = await ChapterCache.get(aid, v.illus!);
        if (content != null) await _dropSkipped(aid, v, content.images);
      }
    }
    await box.put('coverSkipDropped', true);
  }

  /// 图片本来就要显示，下载后存在本机。
  Future<ui.Size> _size(String url) async => imageSize(await _ref.read(imageStoreProvider).load(url));
}

/// 只读图片头部拿宽高，不完整解码。
Future<ui.Size> imageSize(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final size = ui.Size(desc.width.toDouble(), desc.height.toDouble());
  desc.dispose();
  buffer.dispose();
  return size;
}

/// 挑封面时最多看插图章节的前几张
const _checked = 4;

/// 从插图章节的图里挑封面：第一张竖着的（宽不超过高）。第一张常常是连书脊、封底一起的横版展开图，就往后找；
/// 前几张都是横的就还用第一张。没有图返回 ''。
Future<String> chooseCover(List<String> images, Future<ui.Size> Function(String url) sizeOf) async {
  for (final url in images.take(_checked)) {
    final s = await sizeOf(url);
    if (s.width <= s.height) return url;
  }
  return images.firstOrNull ?? '';
}

final volumeCoverQueueProvider = Provider<VolumeCoverQueue>(VolumeCoverQueue.new);

/// 卷数据变了就重建（书架封面、书籍墙）
final volumeChangesProvider = Provider<int>((ref) {
  void listener() => ref.invalidateSelf();
  Volumes.changes.addListener(listener);
  ref.onDispose(() => Volumes.changes.removeListener(listener));
  return Volumes.changes.value;
});
