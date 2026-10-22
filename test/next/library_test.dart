import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/next/library.dart';

RemoteBook r(String bid, {int shelf = 0}) => (bid: bid, title: 't$bid', img: '', shelf: shelf);

void main() {
  test('首次导入：网站书架 2~6 的书进同名分类，默认书架的不分类', () {
    final out = reconcile({}, {'1': r('b1'), '2': r('b2', shelf: 3)}, {}, now: 5, firstImport: true);
    expect(out['1']!.cats, isEmpty);
    expect(out['2']!.cats, ['shelf3']);
    expect(out['2']!.bid, 'b2');
    expect(reconcile({}, {'2': r('b2', shelf: 3)}, {}, now: 5)['2']!.cats, isEmpty);
  });

  test('网站上移出了的书本地也移出；只在本地的、刚加入还没推上去的留着', () {
    final local = {
      'synced': const LibBook(aid: 'synced', title: 'a', img: '', bid: 'x'),
      'local': const LibBook(aid: 'local', title: 'b', img: ''),
      'pending': const LibBook(aid: 'pending', title: 'c', img: '', bid: 'y'),
      'keep': const LibBook(aid: 'keep', title: 'd', img: '', cats: ['c1']),
    };
    final out = reconcile(local, {'keep': r('k')}, {'pending': 'add'}, now: 1);
    expect(out.keys.toSet(), {'local', 'pending', 'keep'});
    expect(out['keep']!.bid, 'k');
    expect(out['keep']!.cats, ['c1']);
  });

  test('本地刚移出、还没推到网站的书，不会被网站书架加回来', () {
    expect(reconcile({}, {'1': r('b1')}, {'1': 'remove'}, now: 1), isEmpty);
  });

  test('网站书架整个是空的（多半页面不对）时不删本地的书', () {
    final local = {'synced': const LibBook(aid: 'synced', title: 'a', img: '', bid: 'x')};
    expect(reconcile(local, {}, {}, now: 1).keys, ['synced']);
  });
}
