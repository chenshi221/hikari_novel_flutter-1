import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wenku8/wenku8_client.dart';
import '../data/wenku8/wenku8_exceptions.dart';
import '../data/wenku8/wenku8_parser.dart';
import '../data/wenku8/wenku8_urls.dart';
import '../data/wenku8/wenku8_charset.dart';
import '../models/bookshelf.dart';
import '../models/common/charset_type.dart';
import '../models/cat_volume.dart';
import '../models/comment_item.dart';
import '../models/content.dart';
import '../models/novel_cover.dart';
import '../models/recommend_block.dart';
import '../models/reply_item.dart';
import 'session.dart';

/// 列表的一页：[maxPage] 为 0 表示不知道总页数。
class PageResult {
  const PageResult(this.items, this.maxPage);

  final List<NovelCover> items;
  final int maxPage;
}

class NovelPage {
  const NovelPage(this.detail, this.catalogue);

  final Wenku8NovelDetail detail;
  final List<CatVolume> catalogue;
}

/// 所有网络请求的入口：每个方法 = 请求页面 + 交给解析层。页面结构不对（多半是没登录）时抛出
/// [Wenku8UnexpectedPageException]，界面据此提示去登录。
class Api {
  Api(this._client, this._urls, this._base);

  final Wenku8Client _client;
  final Wenku8Urls _urls;
  final String _base;

  PageResult _list(String html) => PageResult(Wenku8Parser.novelList(html, baseUrl: _base), Wenku8Parser.maxPage(html));

  Future<PageResult> ranking(String sort, int page) async => _list(await _client.getPage(_urls.ranking(sort, page)));

  Future<PageResult> category(String tag, String sort, int page) async => _list(await _client.getPage(_urls.category(tag, sort, page)));

  Future<PageResult> completed(int page) async => _list(await _client.getPage(_urls.completedNovels(page)));

  Future<PageResult> search(String keyword, {required bool byAuthor, required int page}) async {
    final html = await _client.getPage(byAuthor ? _urls.searchByAuthor(keyword, page) : _urls.searchByTitle(keyword, page));
    if (Wenku8Parser.isErrorPage(html)) throw const Wenku8UnexpectedPageException('搜索太频繁，请 5 秒后再试');
    final only = Wenku8Parser.singleSearchResult(html);
    return only != null ? PageResult([only], 1) : _list(html);
  }

  Future<List<RecommendBlock>> recommend() async => Wenku8Parser.recommend(await _client.getPage(_urls.home()));

  Future<NovelPage> novel(String aid) async {
    final detail = Wenku8Parser.novelDetail(await _client.getPage(_urls.novelDetail(aid)));
    return NovelPage(detail, Wenku8Parser.catalogue(await _client.getPage(_urls.catalogue(aid))));
  }

  Future<Content> chapter(String aid, String cid) async => Wenku8Parser.chapterContent(await _client.getPage(_urls.chapterContent(aid, cid)));

  Future<Bookshelf> bookshelf(int classId) async => Wenku8Parser.bookshelf(await _client.getPage(_urls.bookshelf(classId)), classId);

  /// 加入默认书架。wenku8 返回"出现错误！"页时说明失败（例如书架满了）。
  Future<void> addToBookshelf(String aid) async {
    if (Wenku8Parser.isErrorPage(await _client.getPage(_urls.addToBookshelf(aid)))) throw const Wenku8UnexpectedPageException('加入书架失败，书架可能已满');
  }

  Future<void> removeFromBookshelf(String bid) => _client.getPage(_urls.removeFromBookshelf(bid));

  Future<void> removeBooks(List<String> bids, int classId) =>
      _client.postForm(_urls.bookshelfAction(), {'checkid[]': bids, 'classlist': classId, 'checkall': 'checkall', 'newclassid': -1, 'classid': classId});

  Future<void> moveBooks(List<String> bids, int classId, int newClassId) =>
      _client.postForm(_urls.bookshelfAction(), {'checkid[]': bids, 'classlist': classId, 'checkall': 'checkall', 'newclassid': newClassId, 'classid': classId});

  Future<String> vote(String aid) async => Wenku8Parser.voteResult(await _client.getPage(_urls.vote(aid)));

  Future<List<CommentItem>> comments(String aid, int page) async => Wenku8Parser.comments(await _client.getPage(_urls.comments(aid, page)));

  Future<void> sendComment(String aid, String title, String content) => _client.postForm(
    _urls.sendComment(aid),
    'ptitle=${Wenku8Charset.percentEncodeNonAscii(title, CharsetType.gbk)}&pcontent=${Wenku8Charset.percentEncodeNonAscii(content, CharsetType.gbk)}&Submit=${_urls.submitButtonValue()}',
  );

  Future<void> sendReply(String aid, String rid, String content) =>
      _client.postForm(_urls.sendReply(aid, rid), 'pcontent=${Wenku8Charset.percentEncodeNonAscii(content, CharsetType.gbk)}&Submit=${_urls.submitButtonValue()}');

  Future<List<ReplyItem>> replies(String rid, int page) async => Wenku8Parser.replies(await _client.getPage(_urls.replies(rid, page)));
}

final apiProvider = Provider<Api>((ref) {
  final store = ref.watch(sessionStoreProvider);
  return Api(ref.watch(wenku8ClientProvider), ref.watch(wenku8UrlsProvider), siteBase(store));
});
