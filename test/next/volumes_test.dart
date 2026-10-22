import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hikari_novel_flutter/models/cat_chapter.dart';
import 'package:hikari_novel_flutter/models/cat_volume.dart';
import 'package:hikari_novel_flutter/next/cover_color.dart';
import 'package:hikari_novel_flutter/next/read_state.dart';
import 'package:hikari_novel_flutter/next/volumes.dart';

CatVolume vol(String t, List<String> chapters) => CatVolume(title: t, chapters: [for (final c in chapters) CatChapter(title: c.startsWith('i') ? '插图' : '第$c章', cid: c)]);

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('hikari_vol_test').path);
    await Hive.openBox('session');
  });

  test('一卷的正文章节全读了才算读完（插图章不算），标回未读就不算了', () async {
    await Volumes.saveCatalogue('1', [vol('第一卷', ['i1', 'a', 'b']), vol('第二卷', ['c'])]);
    expect(Volumes.of('1').first.illus, 'i1');
    expect(Volumes.done('1'), isEmpty);

    await ReadState.setRead('1', ['a', 'b'], true);
    expect(Volumes.done('1').keys, ['第一卷']);
    expect(Volumes.allDone().single.$3.title, '第一卷');

    await ReadState.setRead('1', ['b'], false);
    expect(Volumes.done('1'), isEmpty);
  });

  test('卷封面：第一张是横版展开图（连书脊、封底）就用后面第一张竖着的', () async {
    final sizes = {'spread': const Size(2000, 700), 'cover': const Size(700, 1000), 'insert': const Size(700, 1000)};
    Future<Size> sizeOf(String url) async => sizes[url]!;
    expect(await chooseCover(['spread', 'cover', 'insert'], sizeOf), 'cover');
    expect(await chooseCover(['cover', 'spread'], sizeOf), 'cover');
    expect(await chooseCover(['spread'], sizeOf), 'spread'); // 全是横的就还用第一张
    expect(await chooseCover([], sizeOf), '');
  });

  test('封面背景色：取主色调、压低饱和度、调暗', () {
    final red = Uint8List.fromList([for (var i = 0; i < 16; i++) ...[220, 40, 40, 255]]);
    final hsl = HSLColor.fromColor(tintFrom(red));
    expect(hsl.hue, closeTo(0, 1));
    expect(hsl.saturation, closeTo(0.35, 0.01));
    expect(hsl.lightness, closeTo(0.38, 0.01));
    // 白底上的一点颜色不会被冲成纯灰
    final mostlyWhite = Uint8List.fromList([for (var i = 0; i < 15; i++) ...[250, 250, 250, 255], 40, 80, 220, 255]);
    expect(HSLColor.fromColor(tintFrom(mostlyWhite)).hue, closeTo(225, 20));
  });
}
