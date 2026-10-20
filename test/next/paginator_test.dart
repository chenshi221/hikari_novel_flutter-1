import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/next/reader/paginator.dart';
import 'package:hikari_novel_flutter/next/reader/reader_page.dart' show formatChapter;

void main() {
  const style = TextStyle(fontSize: 16, height: 1.5);
  final text = List.generate(300, (i) => '这是第$i行文字，用来测试分页。').join('\n');

  test('切成多页，起点递增且从 0 开始', () {
    final starts = paginate(text, style, const Size(200, 300));
    expect(starts.first, 0);
    expect(starts.length, greaterThan(5));
    for (var i = 1; i < starts.length; i++) {
      expect(starts[i], greaterThan(starts[i - 1]));
    }
    expect(starts.last, lessThan(text.length));
  });

  test('页面更大页数更少', () {
    final small = paginate(text, style, const Size(200, 300)).length;
    final big = paginate(text, style, const Size(200, 600)).length;
    expect(big, lessThan(small));
  });

  test('偏移能找回所在页', () {
    final starts = paginate(text, style, const Size(200, 300));
    expect(pageOfOffset(starts, 0), 0);
    expect(pageOfOffset(starts, starts[3]), 3);
    expect(pageOfOffset(starts, starts[3] + 1), 3);
    expect(pageOfOffset(starts, text.length), starts.length - 1);
  });

  test('空文本只有一页', () => expect(paginate('', style, const Size(200, 300)), [0]));

  test('章节格式化：每段两个全角空格缩进，去掉空行和多余空白', () {
    expect(formatChapter('   第一段\n\n  第二段  \n\n'), '　　第一段\n　　第二段');
    expect(formatChapter(''), '');
  });
}
