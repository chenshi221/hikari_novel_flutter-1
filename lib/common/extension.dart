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
