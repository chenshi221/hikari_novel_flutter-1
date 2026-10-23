import 'package:flutter/painting.dart';

/// 把一章文字按页面大小切页，返回每页第一个字符的偏移（第一页恒为 0）。
///
/// 只负责排版，不关心界面：翻页、进度保存、改字号后重新切页都只用这一个函数。
/// [strut] 要和实际显示正文时用的一样：变色、高亮的文字所在的行会比普通行高一点，不统一行高的话，
/// 切页时量出来每页装得下的行数，和显示出来的对不上，最后一行就被页脚盖住。
List<int> paginate(String text, TextStyle style, Size size, {TextDirection textDirection = TextDirection.ltr, StrutStyle? strut}) {
  if (text.isEmpty) return [0];
  final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: textDirection, strutStyle: strut)..layout(maxWidth: size.width);
  final starts = <int>[0];
  var pageTop = 0.0;
  for (final line in painter.computeLineMetrics()) {
    final bottom = line.baseline + line.descent;
    if (bottom - pageTop > size.height && line.baseline - line.ascent > pageTop) {
      pageTop = line.baseline - line.ascent;
      final offset = painter.getPositionForOffset(Offset(0, pageTop + line.height / 2)).offset;
      if (offset > starts.last) starts.add(offset);
    }
  }
  painter.dispose();
  return starts;
}

/// 字符偏移所在的页码。
int pageOfOffset(List<int> starts, int offset) {
  var page = 0;
  for (var i = 0; i < starts.length; i++) {
    if (starts[i] <= offset) page = i;
  }
  return page;
}

/// 把正文切成句子：按 。！？… 和换行切，太短的并入下一句；返回每句的 [start, end)。
List<(int, int)> splitSentences(String text) {
  final out = <(int, int)>[];
  int? start;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    final blank = ch == '\n' || ch == ' ' || ch == '\u3000';
    if (start == null) {
      if (!blank) start = i;
      continue;
    }
    final stop = ch == '\n' || '。！？!?…'.contains(ch);
    if (!stop) continue;
    var end = i + 1;
    while (end < text.length && '”」』）"\''.contains(text[end])) {
      end++;
    }
    if (ch != '\n' && end - start < 8 && end < text.length && text[end] != '\n') continue; // 太短，并入下一句
    out.add((start, end));
    i = end - 1;
    start = null;
  }
  if (start != null && text.substring(start).trim().isNotEmpty) out.add((start, text.length));
  return out;
}
