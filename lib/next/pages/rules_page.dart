import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../color_picker.dart';
import '../reader/reader_page.dart';
import '../rules.dart';

/// 正则规则管理：替换（去广告、统一用字）和高亮（给人物名染色、点一下写备注）。改动后已打开的章节会重新生成。
class RulesPage extends ConsumerStatefulWidget {
  const RulesPage({super.key});

  @override
  ConsumerState<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends ConsumerState<RulesPage> {
  late List<ReplaceRule> _rules = ReplaceRules.all();

  Future<void> _commit(List<ReplaceRule> next) async {
    await ReplaceRules.save(next);
    ref.invalidate(chapterProvider);
    setState(() => _rules = ReplaceRules.all());
  }

  Future<void> _edit(int? index) async {
    final rule = await showRuleDialog(context, initial: index == null ? null : _rules[index]);
    if (rule == null) return;
    final next = [..._rules];
    final at = index;
    if (at == null) {
      next.add(rule);
    } else {
      next[at] = rule;
    }
    await _commit(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('正则规则'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _edit(null))]),
      body: _rules.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('还没有规则。\n替换：去掉章节里的广告、统一用字。\n高亮：给人物名染色，阅读时点一下可以写备注。', textAlign: TextAlign.center),
              ),
            )
          : ListView(
              children: [
                for (final (i, r) in _rules.indexed)
                  Dismissible(
                    key: ValueKey(r.id),
                    background: Container(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.15)),
                    onDismissed: (_) => _commit([..._rules]..removeAt(i)),
                    child: SwitchListTile(
                      title: Text(r.kind != RuleKind.replace ? r.label : r.pattern, style: r.kind != RuleKind.replace ? TextStyle(color: Color(r.color), fontWeight: FontWeight.w600) : const TextStyle(fontFamily: 'monospace')),
                      subtitle: Text(r.kind != RuleKind.replace ? '${r.kind == RuleKind.color ? '变色' : '高亮'}${r.aid.isNotEmpty ? '（单本书）' : ''} · ${r.pattern}' : (r.replacement.isEmpty ? '替换 → （删除）' : '替换 → ${r.replacement}')),
                      value: r.enabled,
                      onChanged: (v) => _commit([..._rules]..[i] = r.copyWith(enabled: v)),
                      secondary: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(i)),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// 添加 / 编辑一条规则的对话框；返回 null 表示取消。阅读器里选中文字后也用它。
Future<ReplaceRule?> showRuleDialog(BuildContext context, {ReplaceRule? initial}) async {
  final pattern = TextEditingController(text: initial?.pattern ?? '');
  final replacement = TextEditingController(text: initial?.replacement ?? '');
  final name = TextEditingController(text: initial?.name ?? '');
  var kind = initial?.kind ?? RuleKind.replace;
  var color = initial?.color ?? ruleColors.first;
  String? error;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(initial == null || initial.pattern.isEmpty ? '添加规则' : '编辑规则'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<RuleKind>(
                segments: const [ButtonSegment(value: RuleKind.replace, label: Text('替换')), ButtonSegment(value: RuleKind.color, label: Text('变色')), ButtonSegment(value: RuleKind.highlight, label: Text('高亮'))],
                selected: {kind},
                onSelectionChanged: (s) => setLocal(() => kind = s.first),
              ),
              const SizedBox(height: 12),
              TextField(controller: pattern, decoration: InputDecoration(labelText: '匹配（正则）', errorText: error)),
              const SizedBox(height: 12),
              if (kind == RuleKind.replace)
                TextField(controller: replacement, decoration: const InputDecoration(labelText: '替换为', helperText: r'留空表示删除；$1 引用分组'))
              else ...[
                if (kind == RuleKind.highlight) ...[
                  TextField(controller: name, decoration: const InputDecoration(labelText: '名字（备注按它归档）', helperText: '例如人物名，可留空')),
                  const SizedBox(height: 12),
                ],
                ColorPickerField(color: color, highlight: kind == RuleKind.highlight, sample: name.text.isNotEmpty ? name.text : '示例', onChanged: (c) => setLocal(() => color = c)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final e = pattern.text.isEmpty ? '请输入正则' : ReplaceRule.validate(pattern.text);
              if (e != null) {
                setLocal(() => error = e);
              } else {
                Navigator.pop(context, true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return null;
  return (initial ?? const ReplaceRule(pattern: '', replacement: '')).copyWith(pattern: pattern.text, replacement: replacement.text, name: name.text.trim(), kind: kind, color: color);
}
