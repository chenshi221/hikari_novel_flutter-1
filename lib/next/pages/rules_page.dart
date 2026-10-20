import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reader/reader_page.dart';
import '../rules.dart';

/// 正则替换规则管理：添加、编辑、启用/停用、删除。改动后已打开的章节会重新生成。
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
    setState(() => _rules = next);
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
      appBar: AppBar(title: const Text('正则替换'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _edit(null))]),
      body: _rules.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('还没有规则。可以用来去掉章节里的广告、统一用字，例如把「著」换成「着」。', textAlign: TextAlign.center)))
          : ListView(
              children: [
                for (final (i, r) in _rules.indexed)
                  Dismissible(
                    key: ValueKey('$i${r.pattern}'),
                    background: Container(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.15)),
                    onDismissed: (_) => _commit([..._rules]..removeAt(i)),
                    child: SwitchListTile(
                      title: Text(r.pattern, style: const TextStyle(fontFamily: 'monospace')),
                      subtitle: Text(r.replacement.isEmpty ? '→（删除）' : '→ ${r.replacement}'),
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

/// 添加 / 编辑一条替换规则的对话框；返回 null 表示取消。阅读器里选中文字后也用它。
Future<ReplaceRule?> showRuleDialog(BuildContext context, {ReplaceRule? initial}) async {
  final pattern = TextEditingController(text: initial?.pattern ?? '');
  final replacement = TextEditingController(text: initial?.replacement ?? '');
  String? error;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(initial == null ? '添加规则' : '编辑规则'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: pattern, decoration: InputDecoration(labelText: '匹配（正则）', errorText: error)),
            const SizedBox(height: 12),
            TextField(controller: replacement, decoration: const InputDecoration(labelText: '替换为', helperText: r'留空表示删除；$1 引用分组')),
          ],
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
  return (initial ?? const ReplaceRule(pattern: '', replacement: '')).copyWith(pattern: pattern.text, replacement: replacement.text);
}
