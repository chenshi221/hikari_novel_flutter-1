import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// 无痕模式：开着时阅读不记进度、历史、已读章节和统计（手动标已读不受影响）。
/// 记录进度的几个地方直接问 [Incognito.on]，不用一层层传参数。
class Incognito {
  Incognito._();

  static bool get on => Hive.isBoxOpen('session') && Hive.box('session').get('incognito') == true;
}

class IncognitoController extends Notifier<bool> {
  @override
  bool build() => Incognito.on;

  void set(bool v) {
    Hive.box('session').put('incognito', v);
    state = v;
  }
}

final incognitoProvider = NotifierProvider<IncognitoController, bool>(IncognitoController.new);
