import 'package:hive_ce_flutter/hive_flutter.dart';

enum RuleKind { replace, highlight }

/// 高亮规则可选的颜色（ARGB）。
const ruleColors = [0xFFE53935, 0xFFF4511E, 0xFFF9A825, 0xFF43A047, 0xFF00897B, 0xFF1E88E5, 0xFF5E35B1, 0xFFD81B60];

/// 一条正则规则：
/// - 替换：章节正文显示前套用，用来去广告、统一用字
/// - 高亮：把匹配到的文字（比如人物名）染上颜色，点一下可以写备注
class ReplaceRule {
  const ReplaceRule({required this.pattern, required this.replacement, this.enabled = true, this.kind = RuleKind.replace, this.color = 0xFFE53935, this.name = '', this.id = ''});

  final String pattern;
  final String replacement;
  final bool enabled;
  final RuleKind kind;
  final int color;

  /// 高亮规则的名字（比如人物名），备注按它归档；留空时用匹配式
  final String name;

  /// 稳定的编号，备注靠它找到规则
  final String id;

  String get label => name.isEmpty ? pattern : name;

  ReplaceRule copyWith({String? pattern, String? replacement, bool? enabled, RuleKind? kind, int? color, String? name, String? id}) => ReplaceRule(
    pattern: pattern ?? this.pattern,
    replacement: replacement ?? this.replacement,
    enabled: enabled ?? this.enabled,
    kind: kind ?? this.kind,
    color: color ?? this.color,
    name: name ?? this.name,
    id: id ?? this.id,
  );

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

/// 章节里一处高亮：`[start, end)` 是正文里的字符范围。
class Mark {
  const Mark(this.start, this.end, this.rule);

  final int start;
  final int end;
  final ReplaceRule rule;
}

class ReplaceRules {
  ReplaceRules._();

  static Box get _box => Hive.box('session');

  static List<ReplaceRule> all() {
    final out = <ReplaceRule>[];
    for (final (i, e) in ((_box.get('rules') as List?) ?? const []).cast<Map>().indexed) {
      out.add(
        ReplaceRule(
          pattern: e['p'] as String,
          replacement: e['r'] as String,
          enabled: e['e'] as bool,
          kind: (e['k'] as int?) == 1 ? RuleKind.highlight : RuleKind.replace,
          color: (e['c'] as int?) ?? ruleColors.first,
          name: (e['n'] as String?) ?? '',
          id: (e['id'] as String?) ?? 'r$i',
        ),
      );
    }
    return out;
  }

  static Future<void> save(List<ReplaceRule> rules) => _box.put('rules', [
    for (final (i, r) in rules.indexed) {'p': r.pattern, 'r': r.replacement, 'e': r.enabled, 'k': r.kind.index, 'c': r.color, 'n': r.name, 'id': r.id.isEmpty ? 'r${DateTime.now().microsecondsSinceEpoch}$i' : r.id},
  ]);

  /// 依次套用启用的替换规则；替换串里可用 `$1` 引用分组。无效的规则直接跳过。
  static String apply(String text, [List<ReplaceRule>? rules]) {
    var out = text;
    for (final r in rules ?? all()) {
      if (!r.enabled || r.kind != RuleKind.replace || r.pattern.isEmpty) continue;
      try {
        out = out.replaceAllMapped(RegExp(r.pattern, multiLine: true), (m) => r.replacement.replaceAllMapped(RegExp(r'\$(\d)'), (g) => m.group(int.parse(g[1]!)) ?? ''));
      } catch (_) {}
    }
    return out;
  }

  /// 在 [text] 里找出所有高亮：先写的规则优先，重叠的后者让位；结果按位置排序、互不重叠。
  static List<Mark> marks(String text, [List<ReplaceRule>? rules]) {
    final found = <Mark>[];
    for (final r in rules ?? all()) {
      if (!r.enabled || r.kind != RuleKind.highlight || r.pattern.isEmpty) continue;
      try {
        for (final m in RegExp(r.pattern, multiLine: true).allMatches(text)) {
          if (m.end > m.start) found.add(Mark(m.start, m.end, r));
        }
      } catch (_) {}
    }
    final order = {for (final (i, r) in (rules ?? all()).indexed) r.id: i};
    found.sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : (order[a.rule.id] ?? 0).compareTo(order[b.rule.id] ?? 0);
    });
    final out = <Mark>[];
    var end = 0;
    for (final m in found) {
      if (m.start >= end) {
        out.add(m);
        end = m.end;
      }
    }
    return out;
  }
}

/// 高亮人物的备注：每本书一份，按规则编号存。
class RuleNotes {
  RuleNotes._();

  static Box get _box => Hive.box('session');

  static Map<String, String> of(String aid) => ((_box.get('notes:$aid') as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as String));

  static String get(String aid, String ruleId) => of(aid)[ruleId] ?? '';

  static Future<void> set(String aid, String ruleId, String text) {
    final map = of(aid);
    text.trim().isEmpty ? map.remove(ruleId) : map[ruleId] = text;
    return _box.put('notes:$aid', map);
  }
}
