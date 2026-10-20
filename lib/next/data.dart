import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' show parse;

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
import 'cache.dart';
import 'session.dart';

/// 列表的一页：[maxPage] 为 0 表示不知道总页数。
/// 最近一次解析失败的搜索页原文，搜索页的"复制页面源码"用它，方便排查网站结构变化。
String? lastFailedHtml;

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

  /// 取页面；[offline] 为 true 时联网失败可以用上次保存的备份。
  Future<String> _page(String url, {bool offline = false}) async {
    try {
      final html = await _client.getPage(url);
      if (offline) await PageStore.put(url, html);
      return html;
    } on Wenku8UnexpectedPageException {
      rethrow;
    } catch (_) {
      final saved = offline ? PageStore.get(url) : null;
      if (saved == null) rethrow;
      return saved;
    }
  }

  PageResult _list(String html) => PageResult(Wenku8Parser.novelList(html, baseUrl: _base), Wenku8Parser.maxPage(html));

  Future<PageResult> ranking(String sort, int page) async => _list(await _client.getPage(_urls.ranking(sort, page)));

  Future<PageResult> category(String tag, String sort, int page) async => _list(await _client.getPage(_urls.category(tag, sort, page)));

  Future<PageResult> completed(int page) async => _list(await _client.getPage(_urls.completedNovels(page)));

  Future<PageResult> search(String keyword, {required bool byAuthor, required int page}) async {
    final html = await _client.getPage(byAuthor ? _urls.searchByAuthor(keyword, page) : _urls.searchByTitle(keyword, page));
    final doc = parse(html);
    if (Wenku8Parser.isErrorPage(html)) {
      final why = doc.getElementsByClassName('blockcontent').firstOrNull?.text.trim();
      throw Wenku8UnexpectedPageException(why == null || why.isEmpty ? '搜索太频繁，请 5 秒后再试' : why);
    }
    final only = Wenku8Parser.singleSearchResult(html);
    if (only != null) return PageResult([only], 1);
    final result = _list(html);
    if (result.items.isEmpty && page == 1) {
      // 没解析出书：把页面标题和正文开头带出来，方便判断是没有结果、要登录还是被拦截
      final title = doc.querySelector('title')?.text.trim() ?? '';
      final text = (doc.getElementById('content') ?? doc.body)?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      lastFailedHtml = html;
      throw Wenku8UnexpectedPageException('没有搜到结果。页面：$title ${text.length > 120 ? text.substring(0, 120) : text}');
    }
    return result;
  }

  Future<List<RecommendBlock>> recommend() async => Wenku8Parser.recommend(await _page(_urls.home(), offline: true));

  Future<NovelPage> novel(String aid) async {
    final detail = Wenku8Parser.novelDetail(await _page(_urls.novelDetail(aid), offline: true));
    return NovelPage(detail, Wenku8Parser.catalogue(await _page(_urls.catalogue(aid), offline: true)));
  }

  /// 只取目录（检查更新用，比 [novel] 少一次请求）。
  Future<List<CatVolume>> catalogue(String aid) async => Wenku8Parser.catalogue(await _page(_urls.catalogue(aid), offline: true));

  Future<Content> chapter(String aid, String cid) async => Wenku8Parser.chapterContent(await _client.getPage(_urls.chapterContent(aid, cid)));

  Future<Bookshelf> bookshelf(int classId) async => Wenku8Parser.bookshelf(await _page(_urls.bookshelf(classId), offline: true), classId);

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
