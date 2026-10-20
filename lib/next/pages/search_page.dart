import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../data.dart';
import '../widgets.dart';

/// 搜索：按书名 / 作者，记住最近 20 条搜索词。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.author});

  /// 从详情页点作者进来时直接按作者搜索
  final String? author;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  late bool _byAuthor = widget.author != null;
  String? _keyword;
  late final Box _box = Hive.box('session');

  List<String> get _history => ((_box.get('searchHistory') as List?) ?? const []).cast<String>();

  @override
  void initState() {
    super.initState();
    if (widget.author != null) {
      _controller.text = widget.author!;
      _keyword = widget.author;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search([String? text]) {
    final keyword = (text ?? _controller.text).trim();
    if (keyword.isEmpty) return;
    _controller.text = keyword;
    FocusScope.of(context).unfocus();
    _box.put('searchHistory', [keyword, ..._history.where((e) => e != keyword)].take(20).toList());
    setState(() => _keyword = keyword);
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: widget.author == null,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: _byAuthor ? '搜索作者' : '搜索书名', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
          onSubmitted: _search,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _search),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('书名')), ButtonSegment(value: true, label: Text('作者'))],
              selected: {_byAuthor},
              onSelectionChanged: (s) => setState(() {
                _byAuthor = s.first;
                if (_keyword != null) _search();
              }),
            ),
          ),
          Expanded(
            child: _keyword == null
                ? ListView(
                    children: [
                      for (final h in _history)
                        ListTile(leading: const Icon(Icons.history), title: Text(h), onTap: () => _search(h)),
                    ],
                  )
                : PagedNovelGrid(key: ValueKey((_keyword, _byAuthor)), fetch: (page) => api.search(_keyword!, byAuthor: _byAuthor, page: page)),
          ),
        ],
      ),
    );
  }
}
