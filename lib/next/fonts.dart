import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'theme.dart';

/// 阅读器字体：系统默认 / 衬线 / 自己选的字体文件（ttf、otf）。
/// 选的文件复制到应用目录，每次选择换一个新的字体名，避免旧字体被缓存。
class FontStore {
  FontStore._();

  static Box get _box => Hive.box('session');

  static String? get customFamily => _box.get('font:family') as String?;

  /// 启动时把上次选的字体文件重新加载进引擎。
  static Future<void> loadSaved() async {
    final path = _box.get('font:path') as String?;
    final family = customFamily;
    if (path == null || family == null) return;
    final file = File(path);
    if (await file.exists()) await _load(family, await file.readAsBytes());
  }

  static Future<void> _load(String family, Uint8List bytes) async {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  /// 弹出文件选择器并加载；用户取消返回 false。
  static Future<bool> pick() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['ttf', 'otf']);
    final src = file?.path;
    if (src == null) return false;
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'font'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dest = await File(src).copy(p.join(dir.path, 'font_$stamp${p.extension(src)}'));
    final family = 'ReaderFont$stamp';
    await _load(family, await dest.readAsBytes());
    await _box.put('font:path', dest.path);
    await _box.put('font:family', family);
    return true;
  }

  /// 0 系统默认 1 衬线 2 自选；没有自选字体时按系统默认。
  static ({String? family, List<String>? fallback}) resolve(int font) => switch (font) {
    1 => (family: null, fallback: kSerifFallback),
    2 when customFamily != null => (family: customFamily, fallback: null),
    _ => (family: null, fallback: null),
  };
}
