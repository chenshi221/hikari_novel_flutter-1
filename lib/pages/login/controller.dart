import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/main.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/common/constants.dart';
import 'package:hikari_novel_flutter/router/route_path.dart';
import 'package:hikari_novel_flutter/service/api_service.dart';

import '../../common/database/database.dart';
import '../../models/resource.dart';
import '../../parser/parser.dart';
import '../../service/db_service.dart';
import '../../service/local_storage_service.dart';
import '../welcome/controller.dart';

class LoginController extends GetxController {
  RxBool showLoading = true.obs;
  RxInt loadingProgress = 0.obs;
  final CookieManager cookieManager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
  InAppWebViewController? inAppWebViewController;

  /// WebView 的"代数"，切换节点时自增，用作 InAppWebView 的 key，使其以新节点的登录页重建
  RxInt webViewGeneration = 0.obs;
  final InAppWebViewSettings settings = InAppWebViewSettings(isInspectable: kDebugMode, userAgent: kUserAgent["User-Agent"], javaScriptEnabled: true);
  RxString currentUrl = "".obs;

  Rx<PageState> pageState = PageState.success.obs;
  String errorMsg = "";

  Rx<Wenku8Node> wenku8Node = Rx(LocalStorageService.instance.getWenku8Node());

  String get url => "${wenku8Node.value.node}/login.php";

  /// 清除旧 cookie 的任务，saveCookie 前需要等待它完成，避免读到上一次登录残留的 cookie
  late Future<void> _clearCookieTask;

  /// 是否正在保存 cookie / 拉取用户信息，防止多次 onLoadStop 重复执行
  bool _isSaving = false;

  @override
  void onInit() {
    super.onInit();
    _clearCookieTask = cookieManager.deleteAllCookies();
  }

  /// 在登录页切换节点：保存设置，清空 cookie，并用新节点的登录页重建 WebView
  void changeWenku8Node(Wenku8Node n) {
    LocalStorageService.instance.setWenku8Node(n);
    wenku8Node.value = n;
    //同步到其它已打开页面的节点选择
    if (Get.isRegistered<WelcomeController>()) Get.find<WelcomeController>().wenku8Node.value = n;

    _clearCookieTask = cookieManager.deleteAllCookies();
    _isSaving = false;
    inAppWebViewController = null; //旧的 WebView 会随 key 变化被销毁
    currentUrl.value = url;
    errorMsg = "";
    showLoading.value = true;
    loadingProgress.value = 0;
    pageState.value = PageState.success;
    webViewGeneration.value++;
  }

  Future<void> saveCookie(WebUri uri) async {
    showLoading.value = false;
    if (_isSaving) return;
    await _clearCookieTask;

    //存储cookie
    if (uri.toString().contains("wenku8") == true) {
      final getCookie = await cookieManager.getCookies(url: uri);

      bool hasCookie = ["jieqiUserInfo", "jieqiVisitInfo"].every(
        (keyword) => getCookie.any((cookieItem) => cookieItem.name.contains(keyword)),
      ); //getCookie.any((cookieItem) => cookieItem.name == "jieqiUserInfo");
      if (hasCookie) {
        if (_isSaving) return;
        _isSaving = true;
        String cookie = "jieqiUserInfo=${getCookie.firstWhere((cookieItem) => cookieItem.name == "jieqiUserInfo").value};";
        cookie += "jieqiVisitInfo=${getCookie.firstWhere((cookieItem) => cookieItem.name == "jieqiVisitInfo").value}";
        LocalStorageService.instance.setCookie(cookie);
        ApiService.instance.initCookie();

        try {
          await _getUserInfo();
          await _refreshBookshelf();
        } catch (e) {
          LocalStorageService.instance.setCookie(null); //清空cookie
          ApiService.instance.deleteCookie();

          final controller = inAppWebViewController;
          if (controller != null) {
            inAppWebViewController = null;
            controller.dispose(); //销毁webview，停止加载网页
          }

          errorMsg = e.toString();
          pageState.value = PageState.error;
          _isSaving = false;

          return;
        }

        Get.offAllNamed(RoutePath.main);
      }
    }
  }

  Future<void> _getUserInfo() async {
    final data = await ApiService.instance.getUserInfo();
    switch (data) {
      case Success():
        LocalStorageService.instance.setUserInfo(Parser.getUserInfo(data.data));
      case Error():
        {
          throw data.error;
        }
    }
  }

  Future<void> _refreshBookshelf() async {
    await DBService.instance.deleteAllBookshelf();

    final futures = Iterable.generate(6, (index) async {
      await _insertAll(index);
    });
    await Future.wait(futures);
  }

  Future<void> _insertAll(int index) async {
    final result = await ApiService.instance.getBookshelf(classId: index);
    switch (result) {
      case Success():
        {
          final bookshelf = Parser.getBookshelf(result.data, index);
          if (bookshelf.list.isNotEmpty) {
            final insertData = bookshelf.list.map((e) {
              return BookshelfEntityData(aid: e.aid, bid: e.bid, url: e.url, title: e.title, img: e.img, classId: bookshelf.classId.toString());
            });
            await DBService.instance.insertAllBookshelf(insertData);
          }
        }
      case Error():
        {
          throw result.error;
        }
    }
  }
}
