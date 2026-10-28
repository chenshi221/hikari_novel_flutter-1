/// 排行榜（显示名, wenku8 参数）；[rankPeriods] 里的分时间榜单参数是「时间 + 参数」，比如 dayvisit
const rankKinds = [('点击', 'visit'), ('推荐', 'vote'), ('收藏', 'goodnum'), ('字数', 'size'), ('最新更新', 'lastupdate'), ('最新入库', 'postdate')];

/// 有日 / 周 / 月 / 总之分的榜单
const rankPeriodic = {'visit', 'vote'};
const rankPeriods = [('日', 'day'), ('周', 'week'), ('月', 'month'), ('总', 'all')];

/// 网站排行页的参数
String rankParam(String kind, String period) => rankPeriodic.contains(kind) ? '$period$kind' : kind;

/// 分类页的标签（直接作为 wenku8 的参数）
const categoryTags = [
  '校园', '青春', '恋爱', '治愈', '群像', '竞技', '音乐', '美食', '旅行', '欢乐向', '经营', '职场', '斗智', '脑洞', '宅文化', '穿越', '奇幻', '魔法', '异能', '战斗', '科幻', '机战', '战争', '冒险', '龙傲天',
  '悬疑', '犯罪', '复仇', '黑暗', '猎奇', '惊悚', '间谍', '末日', '游戏', '大逃杀', '青梅竹马', '妹妹', '女儿', '大小姐', '性转', '伪娘', '人外', '后宫', '百合', '耽美', 'NTR', '女性视角',
];

/// 分类页的排序（显示名, wenku8 参数）
const categorySorts = [('按更新', '0'), ('按热门', '1'), ('已完结', '2'), ('动画化', '3')];

/// 书架分组 0~5 的显示名
const shelfNames = ['默认书架', '书架 2', '书架 3', '书架 4', '书架 5', '书架 6'];
