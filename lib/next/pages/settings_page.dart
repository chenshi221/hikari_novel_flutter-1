import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/common/wenku8_node.dart';
import '../app_prefs.dart';
import '../backup.dart';
import '../cache.dart';
import '../env.dart';
import '../image_cache.dart';
import '../incognito.dart';
import '../library.dart';
import '../router.dart';
import '../security.dart';
import '../session.dart';
import '../settings.dart';
import '../swipe.dart';
import '../theme.dart';
import '../widgets.dart';

/// 设置分成几组（Mihon 那样），主页能搜索：搜到的条目点一下跳到它所在的那一组。
enum SettingsSection {
  appearance('外观', Icons.palette_outlined, '主题、配色、屏幕方向'),
  reading('阅读', Icons.menu_book_outlined, '翻页方式、字号、朗读、章节滑动'),
  shelf('书架', Icons.auto_stories_outlined, '角标、列数、分类、新书放哪'),
  update('更新', Icons.update_outlined, '自动检查间隔、网络限制、检查哪些书'),
  data('数据与存储', Icons.storage_outlined, '缓存、备份与恢复、同步'),
  security('安全与隐私', Icons.lock_outline, '生物识别锁、防截屏、无痕模式'),
  network('网络', Icons.public, '站点节点、代理、系统网络栈'),
  about('关于', Icons.info_outline, '版本信息');

  const SettingsSection(this.title, this.icon, this.summary);

  final String title;
  final IconData icon;
  final String summary;
}

/// 能搜到的设置项：(标题, 所在分组, 额外关键词)
const _items = <(String, SettingsSection, String)>[
  ('主题', SettingsSection.appearance, '深色 浅色 夜间 跟随系统'),
  ('配色', SettingsSection.appearance, '主题色 颜色'),
  ('屏幕方向', SettingsSection.appearance, '横屏 竖屏 旋转'),
  ('翻页方式', SettingsSection.reading, '滚动 滑动 仿真 覆盖'),
  ('正则规则', SettingsSection.reading, '替换 去广告 高亮 备注'),
  ('字号', SettingsSection.reading, '字体 大小'),
  ('朗读语速', SettingsSection.reading, '听书 tts'),
  ('章节滑动', SettingsSection.reading, '左滑 右滑 已读 书签 手势'),
  ('继续阅读按钮', SettingsSection.shelf, '书架 封面 播放'),
  ('未读角标', SettingsSection.shelf, '数字 角标 徽标'),
  ('缓存角标', SettingsSection.shelf, '数字 角标 已缓存'),
  ('标签显示书数', SettingsSection.shelf, '分类 计数 数量'),
  ('每个标签单独设置', SettingsSection.shelf, '筛选 排序 显示 分类'),
  ('书架列数', SettingsSection.shelf, '网格 竖屏 横屏 每行'),
  ('新书默认分类', SettingsSection.shelf, '加入书架 分类 询问'),
  ('分类管理', SettingsSection.shelf, '新建 删除 排序'),
  ('自动检查更新', SettingsSection.update, '间隔 小时 每天 每周'),
  ('只在 Wi-Fi 下检查', SettingsSection.update, '网络 流量 限制'),
  ('只在充电时检查', SettingsSection.update, '电量 限制'),
  ('跳过已完结的书', SettingsSection.update, '更新 连载'),
  ('跳过没开始读的书', SettingsSection.update, '更新'),
  ('跳过还有未读章节的书', SettingsSection.update, '更新'),
  ('只检查这些分类', SettingsSection.update, '更新 包含'),
  ('不检查这些分类', SettingsSection.update, '更新 排除'),
  ('图片缓存', SettingsSection.data, '封面 插图 清除 存储'),
  ('章节缓存', SettingsSection.data, '正文 清除 存储 自动清理'),
  ('备份', SettingsSection.data, '导出 导入 恢复'),
  ('同步', SettingsSection.data, '坚果云 webdav 多设备'),
  ('生物识别锁', SettingsSection.security, '指纹 面容 密码 锁定'),
  ('防截屏', SettingsSection.security, '录屏 最近任务 隐私'),
  ('无痕模式', SettingsSection.security, '不记录 历史 进度'),
  ('站点节点', SettingsSection.network, 'wenku8.net wenku8.cc'),
  ('HTTP 代理', SettingsSection.network, '梯子 proxy'),
  ('系统网络栈', SettingsSection.network, 'cloudflare tls'),
  ('版本', SettingsSection.about, '关于'),
];

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final hits = q.isEmpty ? const <(String, SettingsSection, String)>[] : _items.where((e) => '${e.$1} ${e.$3} ${e.$2.title}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: contentWidth(ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            decoration: const InputDecoration(hintText: '搜索设置', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          if (q.isNotEmpty) ...[
            if (hits.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('没有匹配的设置'))),
            for (final (title, section, _) in hits)
              ListTile(
                leading: Icon(section.icon),
                title: Text(title),
                subtitle: Text(section.title),
                onTap: () => context.push(Routes.settingsSection(section.name)),
              ),
          ] else
            for (final s in SettingsSection.values)
              ListTile(
                leading: Icon(s.icon),
                title: Text(s.title),
                subtitle: Text(s.summary),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.settingsSection(s.name)),
              ),
        ],
      )),
    );
  }
}

class SettingsSectionPage extends ConsumerStatefulWidget {
  const SettingsSectionPage({super.key, required this.section});

  final SettingsSection section;

  @override
  ConsumerState<SettingsSectionPage> createState() => _SectionState();
}

class _SectionState extends ConsumerState<SettingsSectionPage> {
  @override
  Widget build(BuildContext context) {
    ref.watch(appPrefsProvider);
    final children = switch (widget.section) {
      SettingsSection.appearance => _appearance(),
      SettingsSection.reading => _reading(),
      SettingsSection.shelf => _shelf(),
      SettingsSection.update => _update(),
      SettingsSection.data => _data(),
      SettingsSection.security => _security(),
      SettingsSection.network => _network(),
      SettingsSection.about => _about(),
    };
    return Scaffold(
      appBar: AppBar(title: Text(widget.section.title)),
      body: contentWidth(ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: children)),
    );
  }

  // ---- 小零件 ----

  AppPrefs get _prefs => ref.read(appPrefsProvider.notifier);

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)));

  Widget _switch(String title, String key, bool fallback, {String? subtitle}) =>
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(title), subtitle: subtitle == null ? null : Text(subtitle), value: _prefs.get(key, fallback), onChanged: (v) => _prefs.set(key, v));

  Widget _dropdown<T>(String title, T value, Map<T, String> options, ValueChanged<T> onChanged) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    trailing: DropdownButton<T>(value: value, underline: const SizedBox.shrink(), items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => v == null ? null : onChanged(v)),
  );

  /// 多选分类（更新页的"只检查 / 不检查这些分类"）
  Future<void> _pickCats(String key, String title) async {
    final cats = ref.read(libraryProvider).cats;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('还没有分类，先到「分类管理」建一个')));
      return;
    }
    final chosen = {...AppPrefs.readList(key)};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in cats) CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(c.name), value: chosen.contains(c.id), onChanged: (v) => setLocal(() => v! ? chosen.add(c.id) : chosen.remove(c.id))),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, chosen.toList()), child: const Text('确定'))],
        ),
      ),
    );
    if (result != null) _prefs.set(key, result);
  }

  String _catNames(String key) {
    final ids = AppPrefs.readList(key);
    if (ids.isEmpty) return '不限';
    final cats = ref.read(libraryProvider).cats;
    return ids.map((id) => cats.where((c) => c.id == id).firstOrNull?.name).whereType<String>().join('、');
  }

  // ---- 外观 ----

  List<Widget> _appearance() {
    final mode = ref.watch(themeModeProvider);
    final palette = ref.watch(paletteProvider);
    final theme = Theme.of(context);
    return [
      _label('主题'),
      SegmentedButton<ThemeMode>(
        segments: const [ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')), ButtonSegment(value: ThemeMode.light, label: Text('浅色')), ButtonSegment(value: ThemeMode.dark, label: Text('深色'))],
        selected: {mode},
        onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
      ),
      _label('配色'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (i, p) in appPalettes.indexed)
            ChoiceChip(avatar: CircleAvatar(backgroundColor: p.accentLight, radius: 8), label: Text(p.name), selected: palette == i, onSelected: (_) => ref.read(paletteProvider.notifier).set(i)),
        ],
      ),
      if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) ...[
        _label('屏幕方向'),
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 0, label: Text('竖屏')), ButtonSegment(value: 1, label: Text('自动旋转')), ButtonSegment(value: 2, label: Text('横屏'))],
          selected: {ref.watch(orientationProvider)},
          onSelectionChanged: (s) => ref.read(orientationProvider.notifier).set(s.first),
        ),
        Padding(padding: const EdgeInsets.only(top: 6), child: Text('只影响整个 App 的方向', style: theme.textTheme.bodySmall)),
      ],
    ];
  }

  // ---- 阅读 ----

  List<Widget> _reading() {
    final prefs = ref.watch(readerPrefsProvider);
    final theme = Theme.of(context);
    final swipe = ref.watch(swipePrefsProvider);
    return [
      _label('翻页方式'),
      SegmentedButton<int>(
        segments: const [ButtonSegment(value: 0, label: Text('滚动')), ButtonSegment(value: 1, label: Text('滑动')), ButtonSegment(value: 2, label: Text('仿真')), ButtonSegment(value: 3, label: Text('覆盖'))],
        selected: {prefs.mode},
        onSelectionChanged: (s) => ref.read(readerPrefsProvider.notifier).update(prefs.copyWith(mode: s.first)),
      ),
      const SizedBox(height: 8),
      Text('点击分区、亮度、滤镜、音量键等更多阅读设置，在阅读时点菜单里的「设置」。', style: theme.textTheme.bodySmall),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('正则规则'), subtitle: const Text('替换（去广告、统一用字）和高亮（人物名染色、备注）'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.rules)),
      _label('字号 ${prefs.fontSize.round()}'),
      Slider(min: 14, max: 32, divisions: 18, value: prefs.fontSize, onChanged: (v) => ref.read(readerPrefsProvider.notifier).update(prefs.copyWith(fontSize: v))),
      _label('朗读语速 ${prefs.ttsRate.toStringAsFixed(1)}'),
      Slider(min: 0.1, max: 1.0, divisions: 9, value: prefs.ttsRate, onChanged: (v) => ref.read(readerPrefsProvider.notifier).update(prefs.copyWith(ttsRate: v))),
      _label('章节滑动'),
      Text('在章节列表里左右滑一下，直接做这件事', style: theme.textTheme.bodySmall),
      _dropdown<SwipeAct>('向右滑', swipe.right, {for (final a in SwipeAct.values) a: a.label}, (a) => ref.read(swipePrefsProvider.notifier).set(right: a)),
      _dropdown<SwipeAct>('向左滑', swipe.left, {for (final a in SwipeAct.values) a: a.label}, (a) => ref.read(swipePrefsProvider.notifier).set(left: a)),
    ];
  }

  // ---- 书架 ----

  List<Widget> _shelf() {
    final cats = ref.watch(libraryProvider).cats;
    final def = _prefs.get(P.defaultCat, 'ask');
    final defName = def == 'ask' ? '每次询问' : (def.isEmpty ? '不放进分类' : (cats.where((c) => c.id == def).firstOrNull?.name ?? '每次询问'));
    return [
      _label('封面上显示'),
      _switch('继续阅读按钮', P.resumeButton, true, subtitle: '封面右下角，直接回到上次读的位置'),
      _switch('未读章数角标', P.unreadBadge, true),
      _switch('已缓存章数角标', P.cacheBadge, false),
      _label('标签'),
      _switch('标签后面显示书数', P.tabCounts, false),
      _switch('每个标签单独设置', P.perCat, false, subtitle: '筛选、排序、显示方式各标签各记各的；关掉就全部通用'),
      _label('列数'),
      _dropdown<int>('竖屏', _prefs.get(P.colsPortrait, 0), {0: '自动', for (var i = 2; i <= 8; i++) i: '$i 列'}, (v) => _prefs.set(P.colsPortrait, v)),
      _dropdown<int>('横屏', _prefs.get(P.colsLandscape, 0), {0: '自动', for (var i = 2; i <= 10; i++) i: '$i 列'}, (v) => _prefs.set(P.colsLandscape, v)),
      _label('分类'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('新书默认分类'),
        subtitle: Text(defName),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final v = await showDialog<String>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('加入书架时'),
              children: [
                SimpleDialogOption(onPressed: () => Navigator.pop(context, 'ask'), child: const Text('每次询问')),
                SimpleDialogOption(onPressed: () => Navigator.pop(context, ''), child: const Text('不放进分类')),
                for (final c in cats) SimpleDialogOption(onPressed: () => Navigator.pop(context, c.id), child: Text('放进「${c.name}」')),
              ],
            ),
          );
          if (v != null) _prefs.set(P.defaultCat, v);
        },
      ),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('分类管理'), subtitle: const Text('新建、改名、删除、排序'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.categories)),
    ];
  }

  // ---- 更新 ----

  List<Widget> _update() {
    return [
      _label('自动检查'),
      _dropdown<int>('检查间隔', _prefs.get(P.updInterval, 1), const {0: '不自动检查', 1: '每小时', 6: '每 6 小时', 12: '每 12 小时', 24: '每天', 48: '每 2 天', 168: '每周'}, (v) => _prefs.set(P.updInterval, v)),
      Text('只在 App 开着、或打开 App 时检查，进了后台不会检查。下拉书架、点「更新」页的刷新是手动检查，不受下面的限制。', style: Theme.of(context).textTheme.bodySmall),
      _switch('只在 Wi-Fi 下自动检查', P.updWifi, false),
      _switch('只在充电时自动检查', P.updCharging, false),
      _label('检查哪些书'),
      _switch('跳过已完结的书', P.updSkipDone, false),
      _switch('跳过还没开始读的书', P.updSkipNotStarted, false),
      _switch('跳过还有未读章节的书', P.updSkipUnread, false, subtitle: '只检查已经读完的书，看有没有新章节'),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('只检查这些分类'), subtitle: Text(_catNames(P.updInclude)), trailing: const Icon(Icons.chevron_right), onTap: () => _pickCats(P.updInclude, '只检查这些分类（都不选是不限）')),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('不检查这些分类'), subtitle: Text(_catNames(P.updExclude)), trailing: const Icon(Icons.chevron_right), onTap: () => _pickCats(P.updExclude, '不检查这些分类')),
    ];
  }

  // ---- 数据与存储 ----

  Future<void> _confirm(String title, String content, String ok, Future<void> Function() run) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(ok))],
      ),
    );
    if (yes == true) {
      await run();
      if (mounted) setState(() {});
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _exportBackup() async {
    final file = File('${(await getTemporaryDirectory()).path}/hikari_backup.json');
    await file.writeAsString(Backup.make());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  Future<void> _importBackup() async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
      if (picked == null) return;
      final n = await Backup.restore(utf8.decode(await File(picked.path!).readAsBytes()));
      ref.invalidate(libraryProvider);
      ref.invalidate(readerPrefsProvider);
      ref.invalidate(swipePrefsProvider);
      ref.invalidate(appPrefsProvider);
      _snack('已恢复备份${n > 0 ? '，补回 $n 本书' : ''}。部分设置要重启 App 才生效');
    } catch (e) {
      _snack('恢复失败：$e');
    }
  }

  List<Widget> _data() {
    return [
      _label('存储'),
      if (!isWebPreview)
        FutureBuilder<int>(
          future: ref.read(imageStoreProvider).diskBytes(),
          builder: (context, snap) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('清除图片缓存'),
            subtitle: Text(snap.hasData ? '封面和插图缓存 ${(snap.data! / (1 << 20)).toStringAsFixed(1)} MB' : '计算中…'),
            onTap: () => _confirm('清除图片缓存？', '离线缓存里的插图也会被删掉，联网后重新下载。', '清除', () => ref.read(imageStoreProvider).clearDisk()),
          ),
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('清除章节缓存'),
        subtitle: Text('全部章节正文约 ${ChapterCache.totalLabel()}（只清读过时自动缓存的，整本「离线缓存」的书不动）'),
        onTap: () => _confirm('清除章节缓存？', '读过自动缓存的章节会被删掉，再打开时重新下载；阅读报告里按卷统计的字数会变少。', '清除', () async {
          final n = await ChapterCache.clearAuto();
          if (mounted) _snack('清掉了 $n 章');
        }),
      ),
      _switch('每次打开 App 自动清理章节缓存', P.autoClear, false),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('离线缓存'), subtitle: const Text('整本下载的书'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.cache)),
      _label('备份与恢复'),
      Text('完整备份包含阅读进度、历史、书签、已读章节、统计、规则备注，以及书架、分类、各种设置和自选封面。不含登录信息、WebDAV 密码和缓存的正文。', style: Theme.of(context).textTheme.bodySmall),
      ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.upload_file_outlined), title: const Text('导出完整备份'), subtitle: const Text('生成一个文件，用系统分享发给自己或存起来'), onTap: _exportBackup),
      ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.download_outlined), title: const Text('导入备份'), subtitle: const Text('进度等按同步规则并入；书架里没有的书补上；设置只补本机没有的'), onTap: _importBackup),
      _label('多设备'),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('同步'), subtitle: const Text('通过坚果云 WebDAV 在多台设备间同步进度、书签、统计'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(Routes.sync)),
    ];
  }

  // ---- 安全与隐私 ----

  List<Widget> _security() {
    final incognito = ref.watch(incognitoProvider);
    return [
      _label('锁'),
      if (lockSupported) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('生物识别锁'),
          subtitle: const Text('用指纹、面容或手机锁屏密码解锁 App'),
          value: _prefs.get(P.lock, false),
          onChanged: (v) async {
            if (v && !await authenticate('确认开启 Hikari Novel 的锁')) {
              if (mounted) _snack('验证没通过，或者这台设备没设置锁屏 / 生物识别');
              return;
            }
            _prefs.set(P.lock, v);
          },
        ),
        if (_prefs.get(P.lock, false)) _dropdown<int>('离开多久后锁定', _prefs.get(P.lockAfter, 0), const {0: '立即', 1: '1 分钟', 5: '5 分钟', 15: '15 分钟', 30: '30 分钟'}, (v) => _prefs.set(P.lockAfter, v)),
      ] else
        Text('这个平台不支持生物识别锁', style: Theme.of(context).textTheme.bodySmall),
      if (secureScreenSupported) ...[
        _label('防截屏'),
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 0, label: Text('关')), ButtonSegment(value: 1, label: Text('始终')), ButtonSegment(value: 2, label: Text('仅无痕时'))],
          selected: {_prefs.get(P.secure, 0)},
          onSelectionChanged: (s) => _prefs.set(P.secure, s.first),
        ),
        Padding(padding: const EdgeInsets.only(top: 6), child: Text('开了以后截不了屏、录不了屏，最近任务里也不显示 App 内容', style: Theme.of(context).textTheme.bodySmall)),
      ],
      _label('无痕模式'),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('无痕模式'), subtitle: const Text('开着时不记录阅读进度、历史、已读章节和统计'), value: incognito, onChanged: (v) => ref.read(incognitoProvider.notifier).set(v)),
    ];
  }

  // ---- 网络 ----

  List<Widget> _network() {
    final store = ref.watch(sessionStoreProvider);
    if (isWebPreview) return [const Padding(padding: EdgeInsets.all(32), child: Text('网页预览里不用设置'))];
    return [
      _label('站点节点'),
      SegmentedButton<Wenku8Node>(
        segments: const [ButtonSegment(value: Wenku8Node.wwwWenku8Net, label: Text('wenku8.net')), ButtonSegment(value: Wenku8Node.wwwWenku8Cc, label: Text('wenku8.cc'))],
        selected: {ref.watch(nodeProvider)},
        onSelectionChanged: (s) => ref.read(nodeProvider.notifier).set(s.first),
      ),
      const SizedBox(height: 12),
      TextFormField(initialValue: store.proxy, decoration: const InputDecoration(labelText: 'HTTP 代理', hintText: '127.0.0.1:7890'), onChanged: store.setProxy),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('系统网络栈'),
        subtitle: const Text('用系统自带的网络层发请求，TLS 指纹和浏览器一致，更不容易被 Cloudflare 拦截。填了代理时不生效；改动后重启 App 生效。'),
        value: store.nativeNet,
        onChanged: (v) async {
          await store.setNativeNet(v);
          setState(() {});
        },
      ),
    ];
  }

  // ---- 关于 ----

  List<Widget> _about() => [
    FutureBuilder(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) => ListTile(contentPadding: EdgeInsets.zero, title: const Text('Hikari Novel'), subtitle: Text('轻小说文库第三方客户端 · MIT${snap.hasData ? ' · v${snap.data!.version}+${snap.data!.buildNumber}' : ''}')),
    ),
  ];
}
