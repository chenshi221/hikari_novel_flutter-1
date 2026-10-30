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
import 'unlock.dart';

/// 列表的一页：[maxPage] 为 0 表示不知道总页数。
/// 最近一次解析失败的搜索页原文，搜索页的"复制页面源码"用它，方便排查网站结构变化。
String? lastFailedHtml;

class PageResult {
  const PageResult(this.items, this.maxPage);

  final List<NovelCover> items;
  final int maxPage;
}

class NovelPage {
  const NovelPage(this.detail, this.catalogue, {this.locked = false});

  final Wenku8NovelDetail detail;
  final List<CatVolume> catalogue;

  /// 网站不提供这本书的目录/正文（版权受限或下架），界面据此显示「书籍解锁」入口。
  final bool locked;
}

/// 所有网络请求的入口：每个方法 = 请求页面 + 交给解析层。页面结构不对（多半是没登录）时抛出
/// [Wenku8UnexpectedPageException]，界面据此提示去登录。
class Api {
  Api(this._client, this._urls, this._base, this._scope, {this.unlock});

  final Wenku8Client _client;
  final Wenku8Urls _urls;
  final String _base;

  /// 书籍解锁：网页拒绝提供目录/正文（受限、下架）时，改走文库 App 接口或本地 TXT。
  final UnlockService? unlock;

  bool get _unlockEnabled => unlock?.enabled ?? false;

  /// 当前用户 ID（游客为 guest）：账号私有页面（书架）的离线备份按它分开存。
  final String _scope;

  /// 取页面并解析，带离线备份：
  /// - 联网且解析成功：返回结果并更新备份（解析失败的页面——登录页、错误页、结构变了——绝不写进备份）
  /// - 页面不对（[Wenku8UnexpectedPageException]）：直接抛出，不拿旧备份冒充
  /// - 网络问题（超时、断网、5xx、Cloudflare）：有备份就用备份；[fresh] 时不用备份，直接抛出（和网站书架同步要拿真实的）
  Future<T> _cached<T>(String url, T Function(String html) parse, {bool private = false, String? referer, bool fresh = false}) async {
    final key = private ? '$_scope|$url' : url;
    final String html;
    try {
      html = await _client.getPage(url, charsetParam: false, referer: referer);
    } on Wenku8UnexpectedPageException {
      rethrow;
    } catch (_) {
      final saved = fresh ? null : await PageStore.get(key);
      if (saved == null) rethrow;
      return parse(saved);
    }
    final result = parse(html);
    await PageStore.put(key, html);
    return result;
  }

  /// 提交表单；返回"出现错误！"页（太频繁、没权限等）当失败处理，让界面保留用户输入。
  Future<void> _submit(String url, Object data) async {
    final html = await _client.postForm(url, data);
    if (Wenku8Parser.isErrorPage(html)) {
      final why = parse(html).getElementsByClassName('blockcontent').firstOrNull?.text.trim();
      throw Wenku8UnexpectedPageException(why == null || why.isEmpty ? '提交失败，请稍后再试' : why);
    }
  }

  static String _enc(String value) => Wenku8Charset.percentEncode(value, CharsetType.gbk);

  PageResult _list(String html) => PageResult(Wenku8Parser.novelList(html, baseUrl: _base), Wenku8Parser.maxPage(html));

  Future<PageResult> ranking(String sort, int page) async => _list(await _client.getPage(_urls.ranking(sort, page), charsetParam: false));

  Future<PageResult> category(String tag, String sort, int page) async => _list(await _client.getPage(_urls.category(tag, sort, page), charsetParam: false));

  Future<PageResult> completed(int page) async => _list(await _client.getPage(_urls.completedNovels(page)));

  DateTime _lastSearch = DateTime(0);

  /// 网站限制搜索间隔 5 秒：连续搜索先等够；因为太频繁、超时、网络抖动失败的，等一下自动重试一次。
  /// "没搜到结果"（[lastFailedHtml] 有值）不重试。
  Future<PageResult> search(String keyword, {required bool byAuthor, required int page}) async {
    for (var attempt = 0;; attempt++) {
      final wait = const Duration(seconds: 5, milliseconds: 200) - DateTime.now().difference(_lastSearch);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastSearch = DateTime.now();
      lastFailedHtml = null;
      try {
        return await _search(keyword, byAuthor: byAuthor, page: page);
      } catch (_) {
        if (attempt > 0 || lastFailedHtml != null) rethrow;
      }
    }
  }

  Future<PageResult> _search(String keyword, {required bool byAuthor, required int page}) async {
    final html = await _client.getPage(byAuthor ? _urls.searchByAuthor(keyword, page) : _urls.searchByTitle(keyword, page));
    final doc = parse(html);
    lastFailedHtml = null;
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

  Future<List<RecommendBlock>> recommend() => _cached(_urls.home(), Wenku8Parser.recommend);

  /// 存过的详情和目录（不联网），没存过或解析失败为 null。详情页先显示它，再联网刷新。
  /// 解锁过的书：网站目录一直取不到，用解锁时存下来的目录顶上，打开详情页仍然秒开。
  Future<NovelPage?> saved(String aid) async {
    final detail = await PageStore.get(_urls.novelDetail(aid));
    if (detail == null) return null;
    final cat = await PageStore.get(_urls.catalogue(aid));
    if (cat != null) {
      try {
        final parsed = Wenku8Parser.catalogue(cat);
        if (parsed.isNotEmpty) return NovelPage(Wenku8Parser.novelDetail(detail), parsed);
      } catch (_) {}
    }
    if (_unlockEnabled) {
      final unlocked = await unlock!.storedCatalogue(aid);
      if (unlocked != null && unlocked.isNotEmpty) {
        try {
          return NovelPage(Wenku8Parser.novelDetail(detail), unlocked);
        } catch (_) {}
      }
    }
    return null;
  }

  bool hasDetail(String aid) => PageStore.has(_urls.novelDetail(aid));

  /// 解锁只在网站明确不给时才走：页面解析不出、目录或正文为空。断网、HTTP 错误照常报错；
  /// 游客打不开多半是没登录，也不算，免得登录提示被「解锁本书」盖掉。
  bool get _canUnlock => _unlockEnabled && _scope != 'guest';

  bool _refused(Object e) => _canUnlock && e is Wenku8UnexpectedPageException;

  Future<Wenku8NovelDetail> detail(String aid) async {
    try {
      return await _cached(_urls.novelDetail(aid), Wenku8Parser.novelDetail);
    } catch (e) {
      // 网页详情页异常（改版、拦截）时用文库 App 接口的元信息兜底
      if (_refused(e)) {
        final meta = await unlock!.apiDetail(aid);
        if (meta != null) return meta;
      }
      rethrow;
    }
  }

  Future<NovelPage> novel(String aid) async {
    final d = await detail(aid);
    try {
      return NovelPage(d, await catalogue(aid));
    } catch (e) {
      // 目录被网站屏蔽（例如版权下架）：先给一个「待解锁」的详情页，正文由解锁功能补
      if (_refused(e)) return NovelPage(d, const [], locked: true);
      rethrow;
    }
  }

  /// 只取目录（检查更新用，比 [novel] 少一次请求）。
  Future<List<CatVolume>> catalogue(String aid) async {
    Object error;
    try {
      final list = await _cached(_urls.catalogue(aid), Wenku8Parser.catalogue, referer: '$_base/book/$aid.htm');
      if (list.isNotEmpty || !_canUnlock) return list;
      error = const Wenku8UnexpectedPageException('目录为空');
    } catch (e) {
      if (!_refused(e)) rethrow;
      error = e;
    }
    // TXT 解锁的书 cid 是本地编的（u1、u2…），只能用存下的目录，别被 App 接口的真实 cid 换掉
    final stored = await unlock!.storedCatalogue(aid);
    if (stored != null && UnlockStore.source(aid) == 'txt') return stored;
    final api = await unlock!.apiCatalogue(aid);
    if (api != null && api.isNotEmpty) return api;
    if (stored != null && stored.isNotEmpty) return stored;
    throw error;
  }

  /// 正文。受限章节网页只返回 `null`，解锁开启时改用 App 接口取回全文。
  Future<Content> chapter(String aid, String cid) async {
    Object error;
    try {
      final content = Wenku8Parser.chapterContent(await _client.getPage(_urls.chapterContent(aid, cid), charsetParam: false, referer: _urls.catalogue(aid)));
      if (!_canUnlock || !_isLockedContent(content)) return content;
      error = const Wenku8UnexpectedPageException('本章受版权限制，网站不提供正文');
    } catch (e) {
      if (!_refused(e)) rethrow;
      error = e;
    }
    final content = await unlock!.apiChapter(aid, cid);
    if (content != null) return content;
    throw error;
  }

  /// 受限章节网页只用 `null` 占位（正文页可能已改成错误页，那种情况解析层会直接抛错）。
  /// 只认整整一个 `null`，避免把正文里恰好出现 "null"/"不提供" 的正常章节误判成锁定。
  static bool _isLockedContent(Content c) {
    final text = c.text.trim();
    if (text.isEmpty && c.images.isEmpty) return true;
    return text.toLowerCase() == 'null';
  }

  Future<Bookshelf> bookshelf(int classId, {bool fresh = false}) => _cached(_urls.bookshelf(classId), (html) => Wenku8Parser.bookshelf(html, classId), private: true, fresh: fresh);

  /// 加入默认书架。wenku8 返回"出现错误！"页时说明失败（例如书架满了）。
  Future<void> addToBookshelf(String aid) async {
    if (Wenku8Parser.isErrorPage(await _client.getPage(_urls.addToBookshelf(aid)))) throw const Wenku8UnexpectedPageException('加入书架失败，书架可能已满');
  }

  Future<void> removeFromBookshelf(String bid) => _client.getPage(_urls.removeFromBookshelf(bid));

  Future<void> removeBooks(List<String> bids, int classId) =>
      _submit(_urls.bookshelfAction(), {'checkid[]': bids, 'classlist': classId, 'checkall': 'checkall', 'newclassid': -1, 'classid': classId});

  Future<void> moveBooks(List<String> bids, int classId, int newClassId) =>
      _submit(_urls.bookshelfAction(), {'checkid[]': bids, 'classlist': classId, 'checkall': 'checkall', 'newclassid': newClassId, 'classid': classId});

  Future<String> vote(String aid) async => Wenku8Parser.voteResult(await _client.getPage(_urls.vote(aid)));

  Future<List<CommentItem>> comments(String aid, int page) async => Wenku8Parser.comments(await _client.getPage(_urls.comments(aid, page)));

  Future<void> sendComment(String aid, String title, String content) =>
      _submit(_urls.sendComment(aid), 'ptitle=${_enc(title)}&pcontent=${_enc(content)}&Submit=${_urls.submitButtonValue()}');

  Future<void> sendReply(String aid, String rid, String content) => _submit(_urls.sendReply(aid, rid), 'pcontent=${_enc(content)}&Submit=${_urls.submitButtonValue()}');

  Future<List<ReplyItem>> replies(String rid, int page) async => Wenku8Parser.replies(await _client.getPage(_urls.replies(rid, page)));
}

final apiProvider = Provider<Api>((ref) {
  final node = ref.watch(nodeProvider);
  final scope = ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user.uid : 'guest'));
  return Api(ref.watch(wenku8ClientProvider), ref.watch(wenku8UrlsProvider), siteBase(node), scope, unlock: ref.watch(unlockServiceProvider));
});
