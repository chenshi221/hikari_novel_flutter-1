import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_txt.dart';

String fixture(String name) => File('test/data/wenku8/fixtures/$name').readAsStringSync();

void main() {
  group('真实 OVERLORD 全本 TXT', () {
    late Wenku8TxtBook book;

    setUpAll(() => book = Wenku8Txt.parse(fixture('txt_book.txt'), aid: '1592'));

    test('书名取自 <书名> 行', () {
      expect(book.title, 'OVERLORD不死者之王');
    });

    test('两卷，章名里的卷名和章名拆开', () {
      expect(book.volumes.map((v) => v.title), ['第一卷', '第二卷 黑暗战士']);
      expect(book.volumes[0].chapters.map((c) => c.title), ['prologue', '第一章 开始与结束', '第二章 楼层守护者', 'EPILOGUE', '后记']);
      expect(book.volumes[1].chapters.map((c) => c.title), ['prologue', '第一章 两个冒险者', 'EPILOGUE', '后记']);
    });

    test('cid 按章节顺序编号', () {
      final cids = book.volumes.expand((v) => v.chapters).map((c) => c.cid);
      expect(cids, ['u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8', 'u9']);
      expect(book.texts.keys, containsAll(cids));
    });

    test('正文去掉行首缩进、段落用换行连接', () {
      expect(book.texts['u1'], startsWith('台版 转自 轻之国度\n扫图&录入：天使巧比\n在少女和一名更加幼小的少女面前'));
      expect(book.texts['u2'], startsWith('１\n这个名词是'));
      expect(book.texts['u5'], contains('各位阅读后记的读者，初次见面'));
      expect(book.texts['u9'], contains('各位读者，好久不见了。我是丸山。'));
    });

    test('正文里不出现书名行、横幅和页脚', () {
      for (final text in book.texts.values) {
        expect(text, isNot(contains('轻小说文库')));
        expect(text, isNot(contains('WenKu8')));
        expect(text, isNot(contains('<OVERLORD')));
      }
    });

    test('插图章正文为空，被跳过', () {
      final titles = book.volumes.expand((v) => v.chapters).map((c) => c.title);
      expect(titles, isNot(contains('插图')));
      expect(book.texts.length, 9);
    });
  });

  test('顶格的无卷前缀章节归入当前卷，没有当前卷时新建「正文」', () {
    final book = Wenku8Txt.parse(
      '★☆★☆轻小说文库☆★☆★\n'
      '<测试之书>\n'
      '    这一段在第一个章标题之前，丢掉\n'
      '短篇 某日\n'
      '    短篇正文\n'
      '    这是插画的说明，不是新章节\n'
      '第二卷 黑暗战士 第一章 开始\n'
      '    第一章正文\n'
      'BD特典 BD4 Prologue 上\n'
      '    特典正文\n'
      '◆◇◆◇◆◇◆◇◆◇\n'
      '本文来自轻小说文库\n',
      aid: '1',
    );
    expect(book.title, '测试之书');
    expect(book.volumes.map((v) => v.title), ['正文', '第二卷 黑暗战士']);
    expect(book.volumes[0].chapters.map((c) => c.title), ['短篇 某日']);
    expect(book.volumes[0].chapters.single.cid, 'u1');
    expect(book.texts['u1'], '短篇正文\n这是插画的说明，不是新章节');
    expect(book.volumes[1].chapters.map((c) => c.title), ['第一章 开始', 'BD特典 BD4 Prologue 上']);
    expect(book.volumes[1].chapters.map((c) => c.cid), ['u2', 'u3']);
    expect(book.texts['u3'], '特典正文');
  });

  test('没有 <书名> 时用 fallbackTitle，再没有就用 aid', () {
    const text = '第一卷 prologue\n    正文\n';
    expect(Wenku8Txt.parse(text, aid: '1', fallbackTitle: '备用书名').title, '备用书名');
    expect(Wenku8Txt.parse(text, aid: '1').title, '1');
  });

  test('没有可读章节时抛 FormatException', () {
    expect(() => Wenku8Txt.parse('<空书>\n第一卷 插图\n\n第二卷 插图\n', aid: '1'), throwsFormatException);
    expect(() => Wenku8Txt.parse('', aid: '1'), throwsFormatException);
  });

  group('URL', () {
    test('全本下载地址', () {
      expect(Wenku8Txt.fullBookUrl('1592', type: 'txt'), 'https://dl.wenku8.com/down.php?type=txt&node=1&id=1592');
      expect(Wenku8Txt.fullBookUrl('1592', type: 'utf8', node: 2), 'https://dl.wenku8.com/down.php?type=utf8&node=2&id=1592');
    });

    test('分卷下载地址', () {
      expect(Wenku8Txt.volumeUrl('1592', '12', charset: 'gbk'), 'https://dl.wenku8.com/packtxt.php?aid=1592&vid=12&charset=gbk');
    });

    test('下载类型', () {
      expect(Wenku8Txt.types.map((e) => e.$1), ['txt', 'utf8', 'big5']);
      expect(Wenku8Txt.types.map((e) => e.$2), ['简体 (GBK)', '简体 (UTF-8)', '繁体 (BIG5)']);
    });
  });

  group('decodeBytes', () {
    test('GBK', () {
      expect(Wenku8Txt.decodeBytes(Uint8List.fromList([0xD6, 0xD0, 0xCE, 0xC4]), 'txt'), '中文');
    });

    test('UTF-8', () {
      expect(Wenku8Txt.decodeBytes(Uint8List.fromList(utf8.encode('中文')), 'utf8'), '中文');
    });

    test('Big5', () {
      expect(Wenku8Txt.decodeBytes(Uint8List.fromList([0xA4, 0xA4, 0xA4, 0xE5]), 'big5'), '中文');
    });

    test('认不出的类型按 GBK 处理', () {
      expect(Wenku8Txt.decodeBytes(Uint8List.fromList([0xD6, 0xD0]), 'umd'), '中');
    });

    test('去掉 UTF-8 BOM', () {
      expect(Wenku8Txt.decodeBytes(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('中文')]), 'utf8'), '中文');
    });
  });

  group('sanitizeFileName', () {
    test('去掉文件名非法字符', () {
      expect(Wenku8Txt.sanitizeFileName('a/b:c*?"<>|'), 'a_b_c______');
    });

    test('压缩空白、去掉首尾空白', () {
      expect(Wenku8Txt.sanitizeFileName('  OVERLORD   不死者之王  '), 'OVERLORD 不死者之王');
    });

    test('空名字和纯点号有兜底', () {
      expect(Wenku8Txt.sanitizeFileName(''), 'book');
      expect(Wenku8Txt.sanitizeFileName('   '), 'book');
      expect(Wenku8Txt.sanitizeFileName('...'), 'book');
    });

    test('太长的名字截断', () {
      expect(Wenku8Txt.sanitizeFileName('书' * 100).length, 80);
    });
  });
}
