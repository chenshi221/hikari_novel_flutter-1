import 'package:enough_convert/enough_convert.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

extension Controller on GetInterface {
  T findOrPut<T>(T Function() creator) {
    try {
      return Get.find<T>();
    } catch (_) {
      final instance = creator();
      Get.put<T>(instance);
      return instance;
    }
  }
}

extension ScreenInfo on BuildContext {
  bool isLargeScreen() => MediaQuery.of(this).size.width > MediaQuery.of(this).size.height;

  bool isTabletLikeScreen() => MediaQuery.of(this).size.shortestSide >= 600;

  bool shouldAutoUseDualPage() {
    final size = MediaQuery.of(this).size;
    return size.shortestSide >= 600 && size.width > size.height;
  }
}

extension FormUrlEncoding on String {
  String gbkFormUrlEncode() => _encode(GbkCodec().encode(this));

  String big5FormUrlEncode() => _encode(Big5Codec().encode(this));

  // application/x-www-form-urlencoded：仅保留字母数字和 -_.*，空格转为+，其余字节（含&=+%#等）都编码为 %XX
  String _encode(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      final isUnreserved = (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || '-_.*'.codeUnits.contains(byte);
      if (isUnreserved) {
        buffer.writeCharCode(byte);
      } else if (byte == 0x20) {
        buffer.write('+');
      } else {
        buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return buffer.toString();
  }
}
