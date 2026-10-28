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
import '../theme_squire.dart';
import '../widgets.dart';
import '../x_list.dart';

/// 设置分成几组（Mihon 那样），主页能搜索：搜到的条目点一下跳到它所在的那一组。
enum SettingsSection {
  appearance('外观', Icons.palette_outlined, '主题、配色、屏幕方向'),
  reading('阅读', Icons.book_outlined, '翻页、文字、朗读、章节列表手势'),
  shelf('书架', Icons.auto_stories_outlined, '封面角标、列数、分类管理'),
  update('更新', Icons.update_outlined, '检查频率、网络条件、检查范围'),
  data('数据与存储', Icons.inventory_2_outlined, '缓存、备份与恢复、同步'),
  security('安全与隐私', Icons.lock_outline, '生物识别锁、防截屏、无痕模式'),
  network('网络', Icons.language, '站点节点、代理、系统网络栈'),
  about('关于', Icons.info_outline, '版本信息');

  const SettingsSection(this.title, this.icon, this.summary);

  final String title;
  final IconData icon;
  final String summary;
}

/// 设置首页的分组：组和组之间一道细线
const _homeGroups = [
  [SettingsSection.appearance, SettingsSection.reading, SettingsSection.shelf],
  [SettingsSection.update, SettingsSection.data],
  [SettingsSection.security, SettingsSection.network, SettingsSection.about],
];

/// 能搜到的设置项：(标题, 所在分组, 额外关键词)
const _items = <(String, SettingsSection, String)>[
  ('主题', SettingsSection.appearance, '深色 浅色 夜间 跟随系统'),
  ('配色', SettingsSection.appearance, '主题色 颜色'),
  ('屏幕方向', SettingsSection.appearance, '横屏 竖屏 旋转'),
  ('翻页方式', SettingsSection.reading, '滚动 滑动 仿真 覆盖'),
  ('正则规则', SettingsSection.reading, '替换 去广告 高亮 备注'),
  ('字号', SettingsSection.reading, '字体 大小'),
  ('朗读语速', SettingsSection.reading, '听书 tts'),
  ('章节列表手势', SettingsSection.reading, '左滑 右滑 已读 书签 滑动'),
  ('卷末庆祝卡片', SettingsSection.reading, '仪式 读完 打分 庆祝'),
  ('纯黑深色', SettingsSection.appearance, 'AMOLED 纯黑 省电 oled'),
  ('插画动效', SettingsSection.appearance, '遗迹 晴空 动画 云'),
  ('继续阅读按钮', SettingsSection.shelf, '书架 封面 播放'),
  ('未读角标', SettingsSection.shelf, '数字 角标 徽标'),
  ('缓存角标', SettingsSection.shelf, '数字 角标 已缓存'),
  ('显示分类书籍数量', SettingsSection.shelf, '分类 标签 计数 数量'),
  ('按分类分别设置', SettingsSection.shelf, '筛选 排序 显示 标签'),
  ('书架列数', SettingsSection.shelf, '网格 竖屏 横屏 每行'),
  ('新书默认分类', SettingsSection.shelf, '加入书架 分类 询问'),
  ('分类管理', SettingsSection.shelf, '新建 删除 排序'),
  ('自动检查更新', SettingsSection.update, '间隔 小时 每天 每周'),
  ('仅在 Wi-Fi 下检查', SettingsSection.update, '网络 流量 限制'),
  ('仅在充电时检查', SettingsSection.update, '电量 限制'),
  ('跳过已完结的书', SettingsSection.update, '更新 连载'),
  ('跳过未开始阅读的书', SettingsSection.update, '更新'),
  ('跳过还有未读章节的书', SettingsSection.update, '更新'),
  ('仅检查以下分类', SettingsSection.update, '更新 包含'),
  ('排除以下分类', SettingsSection.update, '更新 不检查'),
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
    final scheme = Theme.of(context).colorScheme;
    final q = _q.trim().toLowerCase();
    final hits = q.isEmpty ? const <(String, SettingsSection, String)>[] : _items.where((e) => '${e.$1} ${e.$3} ${e.$2.title}'.toLowerCase().contains(q)).toList();
    void open(SettingsSection s) => context.push(Routes.settingsSection(s.name));
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: contentWidth(
        ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // 圆角搜索条，和页面底色只差一点
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: '搜索设置',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: scheme.onSurface.withValues(alpha: 0.06),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: scheme.primary)),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            if (q.isNotEmpty) ...[
              if (hits.isEmpty) const XNote('没有匹配的设置'),
              for (final (title, section, _) in hits) XEntry(icon: section.icon, title: title, subtitle: '在「${section.title}」里', onTap: () => open(section)),
            ] else
              for (final (i, group) in _homeGroups.indexed) ...[
                if (i > 0) const XDivider(),
                for (final s in group) XEntry(icon: s.icon, title: s.title, subtitle: s.summary, onTap: () => open(s)),
              ],
          ],
        ),
      ),
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
      body: contentWidth(ListView(padding: const EdgeInsets.only(bottom: 32), children: children)),
    );
  }

  // ---- 小零件 ----

  AppPrefs get _prefs => ref.read(appPrefsProvider.notifier);

  Widget _switch(String title, String key, bool fallback, {String? subtitle}) => XSwitch(title: title, subtitle: subtitle, value: _prefs.get(key, fallback), onChanged: (v) => _prefs.set(key, v));

  /// 能点进下一页的：右边一个箭头
  Widget _link(String title, String? subtitle, VoidCallback onTap) => XTile(
    title: title,
    subtitle: subtitle,
    onTap: onTap,
    trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
  );

  /// 多选分类（更新页的"只检查 / 不检查这些分类"）
  Future<void> _pickCats(String key, String title) async {
    final cats = ref.read(libraryProvider).cats;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('还没有分类，请先在「分类管理」中新建')));
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
    final scheme = Theme.of(context).colorScheme;
    return [
      const XGroupTitle('主题'),
      XSegments<ThemeMode>(value: mode, options: const {ThemeMode.system: '跟随系统', ThemeMode.light: '浅色', ThemeMode.dark: '深色'}, onChanged: (v) => ref.read(themeModeProvider.notifier).set(v)),
      _switch('纯黑深色', P.pureBlack, false, subtitle: '深色模式下使用纯黑背景，适合 OLED 屏幕，更省电'),
      const XDivider(),
      const XGroupTitle('配色'),
      // 一排色点：点一下换，选中的外面一圈
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final (i, p) in appPalettes.indexed)
              GestureDetector(
                onTap: () => ref.read(paletteProvider.notifier).set(i),
                child: SizedBox(
                  width: 60,
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: palette == i ? scheme.onSurface : Colors.transparent, width: 2)),
                        // 插画主题的色点直接是一小块插画
                        child: p.scene ? const ClipOval(child: RuinsScene(animate: false, horizon: 0.8)) : DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: p.accentLight)),
                      ),
                      const SizedBox(height: 4),
                      Text(p.name.split('·').first, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: palette == i ? FontWeight.w700 : null, color: palette == i ? scheme.onSurface : scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      if (appPalettes[palette].scene) _switch('插画动效', P.sceneMotion, true, subtitle: '云朵缓慢飘动、旗帜轻轻摆动；关闭可节省电量'),
      if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) ...[
        const XDivider(),
        const XGroupTitle('屏幕方向'),
        XSegments<int>(subtitle: '控制 App 界面的显示方向', value: ref.watch(orientationProvider), options: const {0: '竖屏', 1: '自动旋转', 2: '横屏'}, onChanged: (v) => ref.read(orientationProvider.notifier).set(v)),
      ],
    ];
  }

  // ---- 阅读 ----

  List<Widget> _reading() {
    final prefs = ref.watch(readerPrefsProvider);
    final swipe = ref.watch(swipePrefsProvider);
    void set(ReaderPrefs p) => ref.read(readerPrefsProvider.notifier).update(p);
    return [
      const XGroupTitle('翻页'),
      XChoice<int>(title: '翻页方式', value: prefs.mode, options: const {0: '上下滚动', 1: '左右滑动', 2: '仿真翻页', 3: '覆盖翻页'}, onChanged: (v) => set(prefs.copyWith(mode: v))),
      const XNote('点击区域、亮度、滤镜、音量键等更多选项，请在阅读界面的菜单「设置」中调整。'),
      const XDivider(),
      const XGroupTitle('文字'),
      XSlider(
        title: '字号',
        label: '${prefs.fontSize.round()}',
        slider: Slider(min: 14, max: 32, divisions: 18, value: prefs.fontSize, onChanged: (v) => set(prefs.copyWith(fontSize: v))),
      ),
      _link('正则规则', '用正则替换正文（去广告、统一用字），或给人名等关键词着色、添加备注', () => context.push(Routes.rules)),
      const XDivider(),
      const XGroupTitle('朗读'),
      XSlider(
        title: '语速',
        label: prefs.ttsRate.toStringAsFixed(1),
        slider: Slider(min: 0.1, max: 1.0, divisions: 9, value: prefs.ttsRate, onChanged: (v) => set(prefs.copyWith(ttsRate: v))),
      ),
      const XDivider(),
      const XGroupTitle('章节列表手势'),
      XChoice<SwipeAct>(title: '右滑操作', value: swipe.right, options: {for (final a in SwipeAct.values) a: a.label}, onChanged: (a) => ref.read(swipePrefsProvider.notifier).set(right: a)),
      XChoice<SwipeAct>(title: '左滑操作', value: swipe.left, options: {for (final a in SwipeAct.values) a: a.label}, onChanged: (a) => ref.read(swipePrefsProvider.notifier).set(left: a)),
      const XNote('在章节列表中左右滑动某一章，即可执行对应操作。'),
      const XDivider(),
      const XGroupTitle('卷末'),
      _switch('卷末庆祝卡片', P.volumeDone, true, subtitle: '读完一卷进入下一卷时，展示本卷用时与字数，并可评分'),
    ];
  }

  // ---- 书架 ----

  List<Widget> _shelf() {
    final cats = ref.watch(libraryProvider).cats;
    final def = _prefs.get(P.defaultCat, 'ask');
    return [
      const XGroupTitle('封面'),
      _switch('继续阅读按钮', P.resumeButton, true, subtitle: '显示在封面右下角，点按回到上次阅读位置'),
      _switch('未读章数角标', P.unreadBadge, true),
      _switch('已缓存章数角标', P.cacheBadge, false),
      const XDivider(),
      const XGroupTitle('分类标签'),
      _switch('显示分类书籍数量', P.tabCounts, false),
      _switch('按分类分别设置', P.perCat, false, subtitle: '筛选、排序和显示方式按分类分别保存；关闭后所有分类共用'),
      const XDivider(),
      const XGroupTitle('列数'),
      XChoice<int>(title: '竖屏', value: _prefs.get(P.colsPortrait, 0), options: {0: '自动', for (var i = 2; i <= 8; i++) i: '$i 列'}, onChanged: (v) => _prefs.set(P.colsPortrait, v)),
      XChoice<int>(title: '横屏', value: _prefs.get(P.colsLandscape, 0), options: {0: '自动', for (var i = 2; i <= 10; i++) i: '$i 列'}, onChanged: (v) => _prefs.set(P.colsLandscape, v)),
      const XDivider(),
      const XGroupTitle('分类'),
      XChoice<String>(
        title: '新书默认分类',
        subtitle: '加入书架时自动归入的分类',
        // 选过的分类后来被删了，就当"每次询问"
        value: def == 'ask' || def.isEmpty || cats.any((c) => c.id == def) ? def : 'ask',
        options: {'ask': '每次询问', '': '不分类', for (final c in cats) c.id: c.name},
        onChanged: (v) => _prefs.set(P.defaultCat, v),
      ),
      _link('分类管理', '新建、重命名、删除和排序', () => context.push(Routes.categories)),
    ];
  }

  // ---- 更新 ----

  List<Widget> _update() {
    return [
      const XGroupTitle('自动检查'),
      XChoice<int>(title: '检查间隔', value: _prefs.get(P.updInterval, 1), options: const {0: '不自动检查', 1: '每小时', 6: '每 6 小时', 12: '每 12 小时', 24: '每天', 48: '每 2 天', 168: '每周'}, onChanged: (v) => _prefs.set(P.updInterval, v)),
      _switch('仅在 Wi-Fi 下检查', P.updWifi, false),
      _switch('仅在充电时检查', P.updCharging, false),
      const XNote('仅在 App 运行时检查，进入后台后不会检查。下拉书架或在「更新」页点刷新属于手动检查，不受以上限制。'),
      const XDivider(),
      const XGroupTitle('检查范围'),
      _switch('跳过已完结的书', P.updSkipDone, false),
      _switch('跳过未开始阅读的书', P.updSkipNotStarted, false),
      _switch('跳过还有未读章节的书', P.updSkipUnread, false, subtitle: '只检查已读到最新章节的书'),
      _link('仅检查以下分类', _catNames(P.updInclude), () => _pickCats(P.updInclude, '仅检查以下分类（不选则不限）')),
      _link('排除以下分类', _catNames(P.updExclude), () => _pickCats(P.updExclude, '排除以下分类')),
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
      _snack('已恢复备份${n > 0 ? '，补回 $n 本书' : ''}。部分设置需重启 App 后生效');
    } catch (e) {
      _snack('恢复失败：$e');
    }
  }

  List<Widget> _data() {
    return [
      const XGroupTitle('存储'),
      if (!isWebPreview)
        FutureBuilder<int>(
          future: ref.read(imageStoreProvider).diskBytes(),
          builder: (context, snap) => XTile(
            title: '清除图片缓存',
            subtitle: snap.hasData ? '封面与插图，共 ${(snap.data! / (1 << 20)).toStringAsFixed(1)} MB' : '正在计算…',
            onTap: () => _confirm('清除图片缓存？', '离线缓存中的插图也会被清除，联网后会重新下载。', '清除', () => ref.read(imageStoreProvider).clearDisk()),
          ),
        ),
      XTile(
        title: '清除章节缓存',
        subtitle: '阅读时自动缓存的正文，共约 ${ChapterCache.totalLabel()}；不影响「离线缓存」中整本下载的书',
        onTap: () => _confirm('清除章节缓存？', '阅读时自动缓存的章节将被删除，再次打开时重新下载；阅读报告中按卷统计的字数可能减少。', '清除', () async {
          final n = await ChapterCache.clearAuto();
          if (mounted) _snack('已清除 $n 章');
        }),
      ),
      _switch('启动时自动清理章节缓存', P.autoClear, false),
      _link('离线缓存', '管理整本下载的书', () => context.push(Routes.cache)),
      const XDivider(),
      const XGroupTitle('备份与恢复'),
      XTile(title: '导出完整备份', subtitle: '生成备份文件，通过系统分享保存或发送', onTap: _exportBackup),
      XTile(title: '导入备份', subtitle: '阅读数据按同步规则合并，补回书架中缺少的书；设置只补充本机没有的项', onTap: _importBackup),
      const XNote('完整备份包含阅读进度、历史、书签、已读章节、统计、规则与备注，以及书架、分类、各项设置和自选封面；不含登录信息、WebDAV 密码和已缓存的正文。'),
      const XDivider(),
      const XGroupTitle('多设备'),
      _link('同步', '通过 WebDAV（如坚果云）在多台设备间同步阅读进度、书签和统计', () => context.push(Routes.sync)),
    ];
  }

  // ---- 安全与隐私 ----

  List<Widget> _security() {
    final incognito = ref.watch(incognitoProvider);
    return [
      const XGroupTitle('应用锁'),
      if (lockSupported) ...[
        XSwitch(
          title: '生物识别锁',
          subtitle: '用指纹、面容或手机锁屏密码解锁 App',
          value: _prefs.get(P.lock, false),
          onChanged: (v) async {
            if (v && !await authenticate('确认开启 Hikari Novel 的锁')) {
              if (mounted) _snack('验证未通过，或此设备未设置锁屏密码 / 生物识别');
              return;
            }
            _prefs.set(P.lock, v);
          },
        ),
        if (_prefs.get(P.lock, false)) XChoice<int>(title: '离开多久后锁定', value: _prefs.get(P.lockAfter, 0), options: const {0: '立即', 1: '1 分钟', 5: '5 分钟', 15: '15 分钟', 30: '30 分钟'}, onChanged: (v) => _prefs.set(P.lockAfter, v)),
      ] else
        const XNote('当前平台不支持生物识别锁'),
      if (secureScreenSupported) ...[
        const XDivider(),
        const XGroupTitle('防截屏'),
        XSegments<int>(subtitle: '开启后禁止截屏和录屏，最近任务中也不显示 App 内容', value: _prefs.get(P.secure, 0), options: const {0: '关', 1: '始终', 2: '仅无痕时'}, onChanged: (v) => _prefs.set(P.secure, v)),
      ],
      const XDivider(),
      const XGroupTitle('无痕'),
      XSwitch(title: '无痕模式', subtitle: '开启期间不记录阅读进度、历史、已读章节和统计', value: incognito, onChanged: (v) => ref.read(incognitoProvider.notifier).set(v)),
    ];
  }

  // ---- 网络 ----

  List<Widget> _network() {
    final store = ref.watch(sessionStoreProvider);
    if (isWebPreview) return [const XNote('网页预览无需设置')];
    return [
      const XGroupTitle('站点节点'),
      XSegments<Wenku8Node>(value: ref.watch(nodeProvider), options: const {Wenku8Node.wwwWenku8Net: 'wenku8.net', Wenku8Node.wwwWenku8Cc: 'wenku8.cc'}, onChanged: (v) => ref.read(nodeProvider.notifier).set(v)),
      const XDivider(),
      const XGroupTitle('连接'),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: TextFormField(initialValue: store.proxy, decoration: const InputDecoration(labelText: 'HTTP 代理', hintText: '127.0.0.1:7890'), onChanged: store.setProxy),
      ),
      XSwitch(
        title: '系统网络栈',
        subtitle: '使用系统网络层发送请求，TLS 指纹与浏览器一致，不易被 Cloudflare 拦截。设置代理时不生效；修改后需重启 App。',
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
      builder: (context, snap) => XTile(title: 'Hikari Novel', subtitle: '轻小说文库第三方客户端 · MIT${snap.hasData ? ' · v${snap.data!.version}+${snap.data!.buildNumber}' : ''}'),
    ),
  ];
}
