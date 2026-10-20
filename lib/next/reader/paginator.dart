import 'package:flutter/painting.dart';

/// 把一章文字按页面大小切页，返回每页第一个字符的偏移（第一页恒为 0）。
///
/// 只负责排版，不关心界面：翻页、进度保存、改字号后重新切页都只用这一个函数。
List<int> paginate(String text, TextStyle style, Size size, {TextDirection textDirection = TextDirection.ltr}) {
  if (text.isEmpty) return [0];
  final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: textDirection)..layout(maxWidth: size.width);
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
