import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// 书架、自动更新、安全这几组零散的设置，都记在本地 `p.<名字>` 里。
/// 界面里 `ref.watch(appPrefsProvider)` 之后用 [AppPrefs.get] 读，用 `ref.read(appPrefsProvider.notifier).set` 写；
/// 不经 Riverpod 的地方（自动更新、启动清理）用静态的 [AppPrefs.read]。
class AppPrefs extends Notifier<int> {
  static Box get _box => Hive.box('session');

  static T read<T>(String key, T fallback) {
    final v = _box.get('p.$key');
    return v is T ? v : fallback;
  }

  /// 存的是列表时按字符串列表读（Hive 读出来是 `List<dynamic>`）
  static List<String> readList(String key) => ((_box.get('p.$key') as List?) ?? const []).cast<String>();

  static Future<void> write(String key, Object? value) => _box.put('p.$key', value);

  @override
  int build() => 0;

  T get<T>(String key, T fallback) => read(key, fallback);

  void set(String key, Object? value) {
    _box.put('p.$key', value);
    state++;
  }
}

final appPrefsProvider = NotifierProvider<AppPrefs, int>(AppPrefs.new);

/// 设置名（集中放一处，免得拼错）
class P {
  P._();

  // 书架
  static const resumeButton = 'shelf.resume'; // bool，封面上的"继续阅读"按钮
  static const unreadBadge = 'shelf.unreadBadge'; // bool
  static const cacheBadge = 'shelf.cacheBadge'; // bool
  static const tabCounts = 'shelf.tabCounts'; // bool，标签后面显示书数
  static const perCat = 'shelf.perCat'; // bool，每个标签单独的筛选 / 排序 / 显示
  static const colsPortrait = 'shelf.colsPortrait'; // int，0 自动
  static const colsLandscape = 'shelf.colsLandscape'; // int，0 自动
  static const defaultCat = 'shelf.defaultCat'; // String，'ask' 每次问，'' 不放进分类，其余是分类 id

  // 自动更新
  static const updInterval = 'upd.interval'; // int 小时，0 不自动
  static const updWifi = 'upd.wifi'; // bool 只在 Wi-Fi 下自动更新
  static const updCharging = 'upd.charging'; // bool 只在充电时自动更新
  static const updSkipDone = 'upd.skipDone'; // bool 跳过已完结的
  static const updSkipNotStarted = 'upd.skipNotStarted'; // bool 跳过还没开始读的
  static const updSkipUnread = 'upd.skipUnread'; // bool 跳过还有未读章节的
  static const updInclude = 'upd.include'; // List<String> 只更新这些分类，空是不限
  static const updExclude = 'upd.exclude'; // List<String> 不更新这些分类

  // 数据
  static const autoClear = 'data.autoClear'; // bool 每次打开 App 自动清理读过时缓存的章节

  // 安全
  static const lock = 'sec.lock'; // bool 生物识别锁
  static const lockAfter = 'sec.lockAfter'; // int 分钟，0 立即
  static const secure = 'sec.secure'; // int 0 关 1 始终 2 仅无痕时
}
