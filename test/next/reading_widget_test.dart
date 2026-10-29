import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/next/reading_widget.dart';
import 'package:hikari_novel_flutter/next/router.dart';

void main() {
  test('点桌面小组件打开的链接对应到 App 里的页面', () {
    expect(ReadingWidget.route(Uri.parse('hikari://reader/123/456')), Routes.reader('123', '456'));
    expect(ReadingWidget.route(Uri.parse('hikari://updates')), Routes.updates);
    expect(ReadingWidget.route(Uri.parse('hikari://shelf')), Routes.bookshelf);
    expect(ReadingWidget.route(Uri.parse('hikari://reader/123')), isNull);
    expect(ReadingWidget.route(null), isNull);
  });
}
