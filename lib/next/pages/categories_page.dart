import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library.dart';

/// 选分类（可多选，一个都不选就是"默认"）。取消返回 null。
Future<List<String>?> pickCategories(BuildContext context, List<LibCategory> cats, List<String> initial) {
  final chosen = {...initial};
  return showDialog<List<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('放到哪些分类'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 一个分类都不选就是放在"默认"；勾它会清掉其他分类
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('默认'),
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
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '分类名'), onSubmitted: (v) => Navigator.pop(context, v)),
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
    return Scaffold(
      appBar: AppBar(title: const Text('分类')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await _askName(context, '新建分类');
          if (name != null) await ctl.addCategory(name);
        },
        icon: const Icon(Icons.add),
        label: const Text('新建'),
      ),
      body: lib.cats.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('还没有分类。没放进任何分类的书都在"默认"里。', textAlign: TextAlign.center)))
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: lib.cats.length,
              onReorderItem: (from, to) {
                final list = [...lib.cats];
                list.insert(to, list.removeAt(from));
                ctl.reorderCategories(list);
              },
              itemBuilder: (context, i) {
                final c = lib.cats[i];
                final n = lib.books.values.where((b) => b.cats.contains(c.id)).length;
                return ListTile(
                  key: ValueKey(c.id),
                  title: Text(c.name),
                  subtitle: Text('$n 本'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '改名',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final name = await _askName(context, '改名', c.name);
                          if (name != null) await ctl.renameCategory(c.id, name);
                        },
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('删除「${c.name}」？'),
                              content: const Text('里面的书不会删，只是不再属于这个分类。'),
                              actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除'))],
                            ),
                          );
                          if (ok == true) await ctl.deleteCategory(c.id);
                        },
                      ),
                      ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle))),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
