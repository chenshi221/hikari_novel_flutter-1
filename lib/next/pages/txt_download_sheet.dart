import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../app_prefs.dart';
import '../txt_download.dart';
import '../x_list.dart';

/// 「下载 TXT」底部弹窗：选编码和节点，从 dl.wenku8.com 拉全书 TXT，再交给系统分享（可存到文件、发给自己）。
///
/// 受限、下架的书在网页上下载页会提示「该文章不存在」，但 dl.wenku8.com 的全本下载接口仍然可用，
/// 所以这里直接构造下载地址，不经过网站的书页。
Future<void> showTxtDownloadSheet(BuildContext context, WidgetRef ref, {required String aid, required String title}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _TxtDownloadSheet(aid: aid, title: title),
  );
}

class _TxtDownloadSheet extends ConsumerStatefulWidget {
  const _TxtDownloadSheet({required this.aid, required this.title});

  final String aid;
  final String title;

  @override
  ConsumerState<_TxtDownloadSheet> createState() => _TxtDownloadSheetState();
}

class _TxtDownloadSheetState extends ConsumerState<_TxtDownloadSheet> {
  late String _type = AppPrefs.read(P.unlockType, 'txt');
  late int _node = AppPrefs.read(P.unlockNode, 1);
  bool _busy = false;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ref.read(txtDownloaderProvider).download(aid: widget.aid, title: widget.title, type: _type, node: _node);
      if (!mounted) return;
      setState(() => _busy = false);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: '《${widget.title}》.txt'));
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '下载失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.file_download_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('下载 TXT', style: theme.textTheme.titleMedium)),
                IconButton(onPressed: _busy ? null : () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close)),
              ],
            ),
            Text('《${widget.title}》', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('来自 dl.wenku8.com 的全本下载接口，受限/下架的书也能下。下载后可以在系统分享面板里保存到「文件」或用其他阅读器打开。', style: muted),
            const SizedBox(height: 12),
            XSegments<String>(
              title: '编码',
              value: _type,
              options: const {'txt': '简体 (GBK)', 'utf8': '简体 (UTF-8)', 'big5': '繁体 (BIG5)'},
              onChanged: _busy
                  ? (_) {}
                  : (v) {
                      setState(() => _type = v);
                      AppPrefs.write(P.unlockType, v);
                    },
            ),
            const SizedBox(height: 4),
            XSegments<int>(
              title: '下载节点',
              value: _node,
              options: const {1: '节点 1', 2: '节点 2（备用）'},
              onChanged: _busy
                  ? (_) {}
                  : (v) {
                      setState(() => _node = v);
                      AppPrefs.write(P.unlockNode, v);
                    },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _download,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download),
                label: Text(_busy ? '正在下载…' : '下载并分享'),
              ),
            ),
            const SizedBox(height: 8),
            Text('下载的是整本 TXT（含全部卷章）。如果只想在 App 里读，受限书的详情页可以用「解锁本书」直接导入。', style: muted),
          ],
        ),
      ),
    );
  }
}
