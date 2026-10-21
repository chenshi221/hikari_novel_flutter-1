import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:hikari_novel_flutter/common/constants.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_charset.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_client.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_urls.dart';
import 'package:hikari_novel_flutter/models/common/charset_type.dart';
import 'package:hikari_novel_flutter/models/common/language.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';
import 'package:hikari_novel_flutter/models/resource.dart';

import '../common/log.dart';
import 'local_storage_service.dart';

/// 旧页面使用的接口入口。实际请求由 [Wenku8Client] 完成，地址由 [Wenku8Urls] 生成，
/// 这里只负责读取用户设置（节点、语言）并把结果/异常包装成 [Resource]。
class ApiService extends GetxService {
  static ApiService get instance => Get.find<ApiService>();

  Wenku8Node get wenku8Node => LocalStorageService.instance.getWenku8Node();

  late final Wenku8Client client = Wenku8Client(baseUrl: () => wenku8Node.node, charset: () => charsetType, headers: kUserAgent);

  Wenku8Urls get _urls => Wenku8Urls(wenku8Node.node, charsetType);

  Dio get dio => client.dio;

  Future<void> initCookie() async {
    final localCookie = LocalStorageService.instance.getCookie();
    if (localCookie == null) return;
    await client.restoreCookie(localCookie, Wenku8Node.values.map((e) => e.node));
  }

  Future<void> deleteCookie() => client.clearCookie();

  Language get _language => LocalStorageService.instance.getLanguage();

  CharsetType get charsetType {
    if (_language == Language.followSystem) {
      return Get.deviceLocale == Locale("zh", "TW") ? CharsetType.big5Hkscs : CharsetType.gbk;
    }
    return switch (_language) {
      Language.traditionalChinese => CharsetType.big5Hkscs,
      _ => CharsetType.gbk,
    };
  }

  Future<Resource> _get(String url) async {
    try {
      Log.d("$url ${charsetType.name}");
      return Success(await client.getPage(url));
    } catch (e) {
      Log.e(e.toString());
      return Error(e.toString());
    }
  }

  Future<Resource> _post(String url, Object? data) async {
    try {
      return Success(await client.postForm(url, data));
    } catch (e) {
      Log.e(e.toString());
      return Error(e.toString());
    }
  }

  /// 根据排名获取小说列表
  Future<Resource> getNovelByRanking({required String ranking, required int index}) => _get(_urls.ranking(ranking, index));

  /// 根据分类（tag）获取小说列表
  Future<Resource> getNovelByCategory({required String category, required String sort, required int index}) => _get(_urls.category(category, sort, index));

  /// 获取小说信息
  Future<Resource> getNovelDetail({required String aid}) => _get(_urls.novelDetail(aid));

  /// 获取小说的章节目录
  Future<Resource> getCatalogue({required String aid}) => _get(_urls.catalogue(aid));

  /// 加入书库
  Future<Resource> addNovel({required String aid}) => _get(_urls.addToBookshelf(aid));

  /// 移出书库，[delid] 为该书在书架中的 bid
  Future<Resource> removeNovel({required String delid}) => _get(_urls.removeFromBookshelf(delid));

  /// 从书架 [classId] 批量移出书籍
  Future<Resource> removeNovelFromList({required List<String> list, required int classId}) =>
      _post(_urls.bookshelfAction(), {"checkid[]": list, "classlist": classId, "checkall": "checkall", "newclassid": -1, "classid": classId});

  /// 把书籍从书架 [classId] 移动到 [newClassId]
  Future<Resource> moveNovelToOther({required List<String> list, required int classId, required int newClassId}) =>
      _post(_urls.bookshelfAction(), {"checkid[]": list, "classlist": classId, "checkall": "checkall", "newclassid": newClassId, "classid": classId});

  /// 获取书架
  Future<Resource> getBookshelf({required int classId}) => _get(_urls.bookshelf(classId));

  /// 获取其它用户收藏的书籍
  Future<Resource> getBookshelfFromUser({required String uid}) => _get(_urls.userBookshelf(uid));

  /// 获取评论区
  Future<Resource> getComment({required String aid, required int index}) => _get(_urls.comments(aid, index));

  /// 获取回复
  Future<Resource> getReply({required String rid, required int index}) => _get(_urls.replies(rid, index));

  /// 获取推荐页
  Future<Resource> getRecommend() => _get(_urls.home());

  /// 为小说投票
  Future<Resource> novelVote({required String aid}) => _get(_urls.vote(aid));

  /// 根据标题搜索小说
  Future<Resource> searchNovelByTitle({required String title, required int index}) => _get(_urls.searchByTitle(title, index));

  /// 根据作者搜索小说
  Future<Resource> searchNovelByAuthor({required String author, required int index}) => _get(_urls.searchByAuthor(author, index));

  /// 获取用户信息
  Future<Resource> getUserInfo() => _get(_urls.userInfo());

  /// 获取已完结小说的列表
  Future<Resource> getCompletionNovel({required int index}) => _get(_urls.completedNovels(index));

  /// 发表书评
  Future<Resource> sendComment({required String aid, required String title, required String content}) {
    final charset = charsetType;
    final params =
        "ptitle=${Wenku8Charset.percentEncodeNonAscii(title, charset)}"
        "&pcontent=${Wenku8Charset.percentEncodeNonAscii(content, charset)}"
        "&Submit=${_urls.submitButtonValue()}";
    return _post(_urls.sendComment(aid), params);
  }

  /// 发表回复
  Future<Resource> sendReply({required String aid, required String rid, required String content}) {
    final params = "pcontent=${Wenku8Charset.percentEncodeNonAscii(content, charsetType)}&Submit=${_urls.submitButtonValue()}";
    return _post(_urls.sendReply(aid, rid), params);
  }

  /// 获取小说章节内容
  Future<Resource> getNovelContent({required String aid, required String cid}) => _get(_urls.chapterContent(aid, cid));

  /// 获取Github上面的最新版本
  Future<Resource> fetchLatestRelease() async {
    try {
      final response = await Dio(BaseOptions(headers: kUserAgent)).get(kLatestUrl);
      return Success(response.data);
    } catch (e) {
      return Error(e.toString());
    }
  }
}
