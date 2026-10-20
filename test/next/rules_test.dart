import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/next/rules.dart';

void main() {
  test('按顺序套用规则，支持分组引用', () {
    final rules = [
      const ReplaceRule(pattern: r'(\d+)话', replacement: r'第$1话'),
      const ReplaceRule(pattern: '广告', replacement: ''),
    ];
    expect(ReplaceRules.apply('12话 广告正文', rules), '第12话 正文');
  });

  test('停用的和写错的规则被跳过', () {
    final rules = [const ReplaceRule(pattern: 'a', replacement: 'b', enabled: false), const ReplaceRule(pattern: '(', replacement: 'x')];
    expect(ReplaceRules.apply('aaa(', rules), 'aaa(');
    expect(ReplaceRule.validate('('), isNotNull);
    expect(ReplaceRule.validate('a+'), isNull);
  });
}
