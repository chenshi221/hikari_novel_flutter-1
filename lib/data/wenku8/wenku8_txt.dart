import 'dart:convert' show utf8;
import 'dart:typed_data';

import '../../models/cat_chapter.dart';
import '../../models/cat_volume.dart';
import '../../models/common/charset_type.dart';
import 'wenku8_charset.dart';

/// dl.wenku8.com 全本 TXT 解析出来的书：书名 + 卷/章目录 + 每章正文。
class Wenku8TxtBook {
  const Wenku8TxtBook({required this.title, required this.volumes, required this.texts});

  final String title;

  /// 和网站目录同构，直接交给阅读页用
  final List<CatVolume> volumes;

  /// cid → 正文（段落用 `\n` 连接）
  final Map<String, String> texts;
}

/// 全本 TXT（`https://dl.wenku8.com/down.php?...`）的地址、编码和解析。
///
/// 网站对版权受限 / 下架的书不提供目录和正文，但下载站仍然给全本 TXT，
/// 这里把它拆成和网页目录一样的卷/章结构，正文写进 [CatVolume]/[CatChapter] 用同一套 cid。
/// 纯函数，不读本地存储、不发请求，方便单测。
class Wenku8Txt {
  const Wenku8Txt._();

  /// 下载类型（type 参数, 设置页显示名）
  static const List<(String, String)> types = [('txt', '简体 (GBK)'), ('utf8', '简体 (UTF-8)'), ('big5', '繁体 (BIG5)')];

  /// 全本下载地址。[node] 是下载节点（1 / 2）。
  static String fullBookUrl(String aid, {required String type, int node = 1}) => 'https://dl.wenku8.com/down.php?type=$type&node=$node&id=$aid';

  /// 分卷下载地址（packtxt.php）。[charset] 是服务端编码参数：`gbk` / `utf-8` / `big5`。
  /// 目前解锁走全本，分卷只留着备用。
  static String volumeUrl(String aid, String vid, {required String charset}) => 'https://dl.wenku8.com/packtxt.php?aid=$aid&vid=$vid&charset=$charset';

  /// 按下载类型解码字节。类型认不出时按简体 GBK 处理；顺手去掉 UTF-8 BOM。
  static String decodeBytes(Uint8List bytes, String type) {
    final text = switch (type) {
      'utf8' => utf8.decode(bytes, allowMalformed: true),
      'big5' => Wenku8Charset.decode(bytes, CharsetType.big5Hkscs),
      _ => Wenku8Charset.decode(bytes, CharsetType.gbk),
    };
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  }

  /// 书名转文件名：去掉 Windows / Android 都不允许的字符，压缩空白，避免超长名字。
  static String sanitizeFileName(String title) {
    var name = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
    name = name.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (name.isEmpty) return 'book';
    return name.length > 80 ? name.substring(0, 80) : name;
  }

  /// 卷标题行：`第X卷 ...`
  static final _volumeMark = RegExp(r'^第[0-9一二三四五六七八九十百千零〇两]+卷');

  /// 章标题关键词（不区分大小写）。顺序影响同一行里先匹配到哪个，长的放前面。
  static final _chapterMark = RegExp(
    r'epilogue|prologue|序章|序幕|序篇|终章|終章|尾声|尾聲|后记|後記|插图|插圖|插画|插畫|番外|短篇|过场|過場|间章|間章|第[0-9一二三四五六七八九十百千零〇两]+章|chapter',
    caseSensitive: false,
  );

  /// 纯分隔行（★☆、◆◇、====、———— 之类）
  static final _separator = RegExp(r'^[★☆◆◇=＝*＊~～\-—_·─━\s]{2,}$');

  /// 每行都是 `<书名>` 的书名行
  static final _titleLine = RegExp(r'^<([^<>]+)>$');

  /// 把全本 TXT 拆成卷/章。
  ///
  /// 结构（真实 OVERLORD 全本验证过）：
  /// - 开头横幅 / 结尾页脚跳过，`<OVERLORD不死者之王>` 是书名；
  /// - `第一卷 prologue`、`第二卷 黑暗战士 第一章 两个冒险者` 这类行是章标题；
  /// - 卷名 = 「第X卷」+ 卷名（章节关键词之前的部分），章名 = 关键词开始的部分；
  ///   关键词紧跟「第X卷」时（`第一卷 prologue`）卷名就只有「第X卷」；
  /// - 没有卷前缀但顶格书写、含章关键词的行（`短篇 …`、`BD特典 … Prologue`）算当前卷的章节，
  ///   还没有卷时新建「正文」卷；
  /// - 其余非空行去掉行首空白后作为段落。
  ///
  /// cid 按章节顺序编号 `u1`、`u2`…；正文为空的章节（插图章）直接丢掉，
  /// 一个章节都没有时抛 [FormatException]。
  static Wenku8TxtBook parse(String text, {required String aid, String? fallbackTitle}) {
    final src = text.startsWith('\uFEFF') ? text.substring(1) : text;
    final chapters = <_Chapter>[];
    final paragraphs = <String>[];
    String? title;
    String? volumeTitle;
    String? chapterTitle;

    void flush() {
      final chapter = chapterTitle;
      if (chapter != null && paragraphs.isNotEmpty) {
        chapters.add(_Chapter(volumeTitle ?? '正文', chapter, List<String>.of(paragraphs)));
      }
      paragraphs.clear();
    }

    void open(String volume, [String? chapter]) {
      flush();
      volumeTitle = volume;
      chapterTitle = chapter;
    }

    for (final line in src.split(RegExp(r'\r\n|\r|\n'))) {
      final t = line.trim();
      if (t.isEmpty) continue;

      final titleLine = _titleLine.firstMatch(t);
      if (titleLine != null) {
        title ??= titleLine.group(1)!.trim();
        continue;
      }

      if (_ignored(t)) continue;

      final volume = _volumeMark.firstMatch(t);
      if (volume != null) {
        final prefix = volume.group(0)!;
        final rest = t.substring(prefix.length).trim();
        final mark = _chapterMark.firstMatch(rest);
        if (mark == null) {
          // 只有卷名没有章名：先开卷，后面顶格的章标题再挂进来
          open(rest.isEmpty ? prefix : '$prefix $rest');
        } else if (mark.start == 0) {
          open(prefix, rest);
        } else {
          open('$prefix ${rest.substring(0, mark.start).trim()}', rest.substring(mark.start).trim());
        }
        continue;
      }

      // 章标题行必须顶格，否则正文里的「插图」「尾声」等词会被当成章节
      if (line == line.trimLeft() && _chapterMark.hasMatch(t)) {
        open(volumeTitle ?? '正文', t);
        continue;
      }

      if (chapterTitle == null) continue; // 第一个章标题之前的版权行不要
      paragraphs.add(t);
    }
    flush();

    if (chapters.isEmpty) throw const FormatException('TXT 里没有解析到任何章节');

    final volumes = <CatVolume>[];
    final texts = <String, String>{};
    String? currentVolume;
    var index = 0;
    for (final c in chapters) {
      final cid = 'u${++index}';
      texts[cid] = c.paragraphs.join('\n');
      if (c.volume != currentVolume) {
        currentVolume = c.volume;
        volumes.add(CatVolume(title: c.volume, chapters: []));
      }
      volumes.last.chapters.add(CatChapter(title: c.chapter, cid: cid));
    }

    return Wenku8TxtBook(title: title ?? fallbackTitle ?? aid, volumes: volumes, texts: texts);
  }

  /// 横幅、页脚、纯分隔行
  static bool _ignored(String t) {
    if (t.contains('轻小说文库') || t.toLowerCase().contains('wenku8') || t.contains('本文来自')) return true;
    return _separator.hasMatch(t);
  }
}

class _Chapter {
  const _Chapter(this.volume, this.chapter, this.paragraphs);

  final String volume;
  final String chapter;
  final List<String> paragraphs;
}
