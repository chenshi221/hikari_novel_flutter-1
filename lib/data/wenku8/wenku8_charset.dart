import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';

import '../../models/common/charset_type.dart';

/// wenku8 的页面和查询参数都使用 GBK（简体）或 Big5（繁体）编码，
/// 这里集中处理编码/解码，避免在各处重复写 `%XX` 拼接。
class Wenku8Charset {
  const Wenku8Charset._();

  /// 把字符串按 [charset] 编码后，对**每个字节**做 `%XX` 编码（用于 URL 查询参数）。
  static String percentEncode(String value, CharsetType charset) => _toPercent(_encode(value, charset), onlyNonAscii: false);

  /// 只对非 ASCII 字节做 `%XX` 编码（用于表单提交，ASCII 原样保留）。
  static String percentEncodeNonAscii(String value, CharsetType charset) => _toPercent(_encode(value, charset), onlyNonAscii: true);

  /// 把服务端返回的字节按 [charset] 解码成字符串。
  static String decode(Uint8List bytes, CharsetType charset) => switch (charset) {
    CharsetType.gbk => const GbkCodec(allowInvalid: true).decode(bytes),
    CharsetType.big5Hkscs => const Big5Codec(allowInvalid: true).decode(bytes),
  };

  /// 给 URL 追加 wenku8 识别的 `charset` 参数，让服务端按对应编码返回页面。
  static String withCharsetParam(String url, CharsetType charset) {
    final buffer = StringBuffer(url);
    if (!url.contains("?")) buffer.write("?");
    buffer.write(switch (charset) {
      CharsetType.gbk => "&charset=gbk",
      CharsetType.big5Hkscs => "&charset=big5",
    });
    return buffer.toString();
  }

  static List<int> _encode(String value, CharsetType charset) => switch (charset) {
    CharsetType.gbk => const GbkCodec(allowInvalid: true).encode(value),
    CharsetType.big5Hkscs => const Big5Codec(allowInvalid: true).encode(value),
  };

  static String _toPercent(List<int> bytes, {required bool onlyNonAscii}) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (onlyNonAscii && byte <= 0x7F) {
        buffer.writeCharCode(byte);
      } else {
        buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return buffer.toString();
  }
}
