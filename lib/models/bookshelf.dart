class Bookshelf {
  final List<BookshelfNovelInfo> list;
  final String classId;

  Bookshelf({required this.list, required this.classId});
}

class BookshelfNovelInfo {
  final String bid;
  final String aid;
  final String url;
  final String title;
  final String img;

  BookshelfNovelInfo({required this.bid, required this.aid, required this.url, required this.title, required this.img});
}
