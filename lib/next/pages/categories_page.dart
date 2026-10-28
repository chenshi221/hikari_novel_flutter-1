import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library.dart';
import '../x_list.dart';

/// 选分类（可多选，一个都不选就是"默认"）。取消返回 null。
Future<List<String>?> pickCategories(BuildContext context, List<LibCategory> cats, List<String> initial) {
  final chosen = {...initial};
  return showDialog<List<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('选择分类'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 一个分类都不选就是放在"默认"；勾它会清掉其他分类
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('默认（不分类）'),
                value: chosen.isEmpty,
                onChanged: (v) => setState(chosen.clear),
              ),
              for (final c in cats)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.name),
                  value: chosen.contains(c.id),
                  onChanged: (v) => setState(() => v! ? chosen.add(c.id) : chosen.remove(c.id)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, [for (final c in cats) if (chosen.contains(c.id)) c.id]), child: const Text('确定')),
        ],
      ),
    ),
  );
}

Future<String?> _askName(BuildContext context, String title, [String initial = '']) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '分类名称'), onSubmitted: (v) => Navigator.pop(context, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
      ],
    ),
  ).then((v) => v?.trim().isEmpty ?? true ? null : v!.trim());
}

/// 管理本地分类：新建、改名、删除、拖动排序。分类只存在本机，不影响网站书架。
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final ctl = ref.read(libraryProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    Future<void> create() async {
      final name = await _askName(context, '新建分类');
      if (name != null) await ctl.addCategory(name);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('分类管理')),
      floatingActionButton: lib.cats.isEmpty ? null : FloatingActionButton.extended(onPressed: create, icon: const Icon(Icons.add), label: const Text('新建分类')),
      body: lib.cats.isEmpty
          ? XEmpty(icon: Icons.label_outline, title: '还没有分类', detail: '未归入任何分类的书都在「默认」中。\n分类只保存在本机，不影响网站书架。', action: '新建分类', onAction: create)
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              buildDefaultDragHandles: false,
              header: const XNote('拖动右侧手柄调整顺序。分类只保存在本机，不影响网站书架。'),
              itemCount: lib.cats.length,
              onReorderItem: (from, to) {
                final list = [...lib.cats];
                list.insert(to, list.removeAt(from));
                ctl.reorderCategories(list);
              },
              itemBuilder: (context, i) {
                final c = lib.cats[i];
                final n = lib.books.values.where((b) => b.cats.contains(c.id)).length;
                return Material(
                  key: ValueKey(c.id),
                  color: Colors.transparent,
                  child: XTile(
                    leading: XLeading(icon: Icons.label_outline, color: scheme.primary),
                    title: c.name,
                    subtitle: '$n 本书',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PopupMenuButton<String>(
                          tooltip: '更多',
                          icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'rename', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit_outlined), title: Text('重命名'))),
                            PopupMenuItem(value: 'delete', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline, color: scheme.error), title: Text('删除', style: TextStyle(color: scheme.error)))),
                          ],
                          onSelected: (v) async {
                            if (v == 'rename') {
                              final name = await _askName(context, '重命名分类', c.name);
                              if (name != null) await ctl.renameCategory(c.id, name);
                              return;
                            }
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('删除「${c.name}」？'),
                                content: const Text('分类中的书不会被删除，只是不再属于该分类。'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                                  FilledButton(style: FilledButton.styleFrom(backgroundColor: scheme.error), onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                                ],
                              ),
                            );
                            if (ok == true) await ctl.deleteCategory(c.id);
                          },
                        ),
                        ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_indicator, color: scheme.onSurfaceVariant))),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
