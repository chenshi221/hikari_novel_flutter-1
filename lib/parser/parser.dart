import 'package:get/get.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_exceptions.dart';
import 'package:hikari_novel_flutter/data/wenku8/wenku8_parser.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';
import 'package:hikari_novel_flutter/models/novel_detail.dart';
import 'package:hikari_novel_flutter/models/recommend_block.dart';
import 'package:hikari_novel_flutter/models/reply_item.dart';
import 'package:hikari_novel_flutter/service/api_service.dart';

import '../common/util.dart';
import '../models/bookshelf.dart';
import '../models/cat_volume.dart';
import '../models/comment_item.dart';
import '../models/content.dart';
import '../models/novel_cover.dart';
import '../models/user_info.dart';

/// 旧页面使用的解析入口。实际解析在 [Wenku8Parser]（纯函数、有测试），
/// 这里只补上多语言文案和"相对时间"等显示相关的处理。
class Parser {
  static List<NovelCover> parseToList(String htmlContent) => Wenku8Parser.novelList(htmlContent, baseUrl: ApiService.instance.wenku8Node.node);

  static List<NovelCover> parseOtherBookshelfToList(String html) => Wenku8Parser.userBookshelf(html);

  static NovelDetail getNovelDetail(String html) {
    final d = Wenku8Parser.novelDetail(html);
    final lastUpdate = d.lastUpdate;
    return NovelDetail(
      d.title,
      d.author,
      d.status,
      lastUpdate == null ? "delisted".tr : (Util.getDateTime(lastUpdate) + "update".tr).trim(),
      d.imgUrl,
      d.introduce,
      d.tags,
      d.heat == null ? "not_trending".tr : "heat".tr + d.heat!,
      d.trending == null ? "not_trending".tr : "increase_rate".tr + d.trending!,
      d.isAnimated,
    );
  }

  static int getMaxNum(String html) => Wenku8Parser.maxPage(html);

  static List<RecommendBlock> getRecommend(String html) => Wenku8Parser.recommend(html);

  static List<CatVolume> getCatalogue(String html) => Wenku8Parser.catalogue(html);

  static List<CommentItem> getComment(String html) => Wenku8Parser.comments(html)
      .map(
        (c) => CommentItem(
          rid: c.rid,
          content: c.content,
          viewCount: c.viewCount,
          replyCount: c.replyCount,
          userName: c.userName,
          uid: c.uid,
          time: Util.getDateTime(c.time),
        ),
      )
      .toList();

  static List<ReplyItem> getReply(String html) =>
      Wenku8Parser.replies(html).map((r) => ReplyItem(content: r.content, userName: r.userName, uid: r.uid, time: Util.getDateTime(r.time))).toList();

  static Bookshelf getBookshelf(String html, int classId) => Wenku8Parser.bookshelf(html, classId);

  static String novelVote(String html) => Wenku8Parser.voteResult(html);

  static UserInfo getUserInfo(String html) {
    try {
      return Wenku8Parser.userInfo(html);
    } on Wenku8UnexpectedPageException {
      // 拿到的不是用户详情页（未登录被跳回登录页、Cloudflare 验证页、节点不可用等）
      throw StateError("get_user_info_failed_tip".tr);
    }
  }

  static bool isError(String html) => Wenku8Parser.isErrorPage(html);

  ///判断搜索结果是否只有一个
  static NovelCover? isSearchResultOnlyOne(String html) => Wenku8Parser.singleSearchResult(html);

  static Content getContent(String html) => Wenku8Parser.chapterContent(html);
}
