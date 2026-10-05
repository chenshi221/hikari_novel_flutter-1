import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/bookshelf.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/service/api_service.dart';
import 'package:hikari_novel_flutter/parser/parser.dart';
import 'package:hikari_novel_flutter/pages/main/controller.dart';

import '../../common/database/database.dart';
import '../../service/db_service.dart';

class BookshelfController extends GetxController with GetTickerProviderStateMixin {
  RxInt tabIndex = 0.obs; //保存tab索引位置

  Rx<PageState> pageState = Rx(PageState.bookshelfContent);

  late TabController tabController;
  final List tabs = List.generate(kBookshelfCount, (i) => "$i");

  RxBool isSelectionMode = false.obs;

  @override
  void onInit() {
    tabController = TabController(length: tabs.length, vsync: this, initialIndex: tabIndex.value);
    super.onInit();
  }

  Future<void> refreshDefaultBookshelf() async {
    final data = await fetchBookshelf(0);
    if (data == null) return; //获取失败时保留本地数据
    await DBService.instance.deleteDefaultBookshelf();
    await DBService.instance.insertAllBookshelf(data);
  }

  Future<String> refreshBookshelf() async => await syncBookshelf() ? "update_successfully".tr : "update_failed".tr;

  /// 从服务器拉取全部书架，全部成功后才替换本地数据，避免网络失败时清空本地书架
  static Future<bool> syncBookshelf() async {
    final results = await Future.wait(Iterable.generate(kBookshelfCount, fetchBookshelf));
    if (results.any((r) => r == null)) return false;

    await DBService.instance.deleteAllBookshelf();
    await DBService.instance.insertAllBookshelf(results.expand((r) => r!));
    return true;
  }

  static const kBookshelfCount = 6;

  /// 获取指定书架，失败时返回null
  static Future<List<BookshelfEntityData>?> fetchBookshelf(int index) async {
    final result = await ApiService.instance.getBookshelf(classId: index);
    switch (result) {
      case Success():
        {
          final bookshelf = Parser.getBookshelf(result.data, index);
          return bookshelf.list
              .map((e) => BookshelfEntityData(aid: e.aid, bid: e.bid, url: e.url, title: e.title, img: e.img, classId: bookshelf.classId.toString()))
              .toList();
        }
      case Error():
        {
          return null;
        }
    }
  }
}

class BookshelfContentController extends GetxController {
  final String classId;

  BookshelfContentController({required this.classId});

  final BookshelfController _bookshelfController = Get.find();
  final MainController _mainController = Get.find();

  bool get isSelectionMode => _bookshelfController.isSelectionMode.value;

  Rxn<Bookshelf> bookshelf = Rxn();
  Rx<PageState> pageState = Rx(PageState.loading);
  String errorMsg = "";

  @override
  void onReady() {
    super.onReady();

    DBService.instance.getBookshelfByClassId(classId).listen((bss) async {
      List<BookshelfNovelInfo> list = bss.map((i) => BookshelfNovelInfo(bid: i.bid, aid: i.aid, url: i.url, title: i.title, img: i.img)).toList();

      if (list.isEmpty) {
        bookshelf.value = null;
        pageState.value = PageState.empty;
      } else {
        bookshelf.value = Bookshelf(list: list, classId: classId);
        pageState.value = PageState.success;
      }
    });
  }

  void toggleCoverSelection(String aid) {
    final selected = bookshelf.value!.list.firstWhere((v) => v.aid == aid).isSelected.value;
    bookshelf.value!.list.firstWhere((v) => v.aid == aid).isSelected.value = !selected;
  }

  Future removeNovelFromList() => ApiService.instance.removeNovelFromList(list: getSelectedNovel(), classId: int.parse(classId));

  Future moveNovelToOther(int newClassId) => ApiService.instance.moveNovelToOther(list: getSelectedNovel(), classId: int.parse(classId), newClassId: newClassId);

  List<String> getSelectedNovel() => bookshelf.value!.list.where((v) => v.isSelected.value == true).map((i) => i.bid).toList();

  void exitSelectionMode() {
    _bookshelfController.isSelectionMode.value = false;
    _mainController.showBookshelfBottomActionBar.value = false;
    deselect();
  }

  void enterSelectionMode() {
    _bookshelfController.isSelectionMode.value = true;
    _mainController.showBookshelfBottomActionBar.value = true;
  }

  void deselect() {
    for (final v in bookshelf.value!.list) {
      v.isSelected.value = false;
    }
  }

  void selectAll() {
    for (final v in bookshelf.value!.list) {
      v.isSelected.value = true;
    }
  }
}

class BookshelfSearchController extends GetxController {
  final _bookshelfController = Get.find<BookshelfController>();
  final searchTextEditController = Get.find<TextEditingController>(tag: "searchTextEditController");

  RxList<BookshelfNovelInfo> data = RxList();
  Rx<PageState> pageState = Rx(PageState.placeholder);

  void getBookshelfByKeyword() async {
    data.assignAll(
      (await DBService.instance.getBookshelfByKeyword(
        searchTextEditController.text,
      )).map((e) => BookshelfNovelInfo(bid: e.bid, aid: e.aid, url: e.url, title: e.title, img: e.img)),
    );
    if (data.isEmpty) {
      pageState.value = PageState.empty;
    } else {
      pageState.value = PageState.success;
    }
  }

  void back() => _bookshelfController.pageState.value = PageState.bookshelfContent;
}
