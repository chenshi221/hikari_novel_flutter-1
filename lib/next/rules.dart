import 'package:hive_ce_flutter/hive_flutter.dart';

/// 正则替换规则：在章节正文显示前依次套用，用来去广告、统一用字等。
class ReplaceRule {
  const ReplaceRule({required this.pattern, required this.replacement, this.enabled = true});

  final String pattern;
  final String replacement;
  final bool enabled;

  ReplaceRule copyWith({String? pattern, String? replacement, bool? enabled}) => ReplaceRule(pattern: pattern ?? this.pattern, replacement: replacement ?? this.replacement, enabled: enabled ?? this.enabled);

  /// 正则写错时返回错误说明，正确返回 null。
  static String? validate(String pattern) {
    try {
      RegExp(pattern, multiLine: true);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }
}

class ReplaceRules {
  ReplaceRules._();

  static Box get _box => Hive.box('session');

  static List<ReplaceRule> all() => ((_box.get('rules') as List?) ?? const []).cast<Map>().map((e) => ReplaceRule(pattern: e['p'] as String, replacement: e['r'] as String, enabled: e['e'] as bool)).toList();

  static Future<void> save(List<ReplaceRule> rules) => _box.put('rules', [for (final r in rules) {'p': r.pattern, 'r': r.replacement, 'e': r.enabled}]);

  /// 依次套用启用的规则；替换串里可用 `$1` 引用分组。无效的规则直接跳过。
  static String apply(String text, [List<ReplaceRule>? rules]) {
    var out = text;
    for (final r in rules ?? all()) {
      if (!r.enabled || r.pattern.isEmpty) continue;
      try {
        out = out.replaceAllMapped(RegExp(r.pattern, multiLine: true), (m) => r.replacement.replaceAllMapped(RegExp(r'\$(\d)'), (g) => m.group(int.parse(g[1]!)) ?? ''));
      } catch (_) {}
    }
    return out;
  }
}
