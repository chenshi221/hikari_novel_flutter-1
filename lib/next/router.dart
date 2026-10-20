import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/bookshelf_page.dart';
import 'pages/comments_page.dart';
import 'pages/discover_page.dart';
import 'pages/home_shell.dart';
import 'pages/library_pages.dart';
import 'pages/login_page.dart';
import 'pages/novel_page.dart';
import 'pages/profile_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/splash_page.dart';
import 'reader/reader_page.dart';
import 'session.dart';

class Routes {
  const Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const discover = '/discover';
  static const bookshelf = '/bookshelf';
  static const profile = '/profile';
  static const search = '/search';
  static const settings = '/settings';
  static const history = '/history';
  static const cache = '/cache';

  static String searchAuthor(String author) => '/search?author=${Uri.encodeQueryComponent(author)}';
  static String novel(String aid) => '/novel/$aid';
  static String comments(String aid) => '/novel/$aid/comments';
  static String replies(String aid, String rid) => '/novel/$aid/comments/$rid';
  static String reader(String aid, String cid) => '/reader/$aid/$cid';
}

/// 检查登录状态时停在启动页，检查完一律进主界面；登录页由用户按需 push 打开。
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<SessionState>(ref.read(sessionProvider));
  ref.listen(sessionProvider, (_, next) => refresh.value = next);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final checking = ref.read(sessionProvider) is SessionChecking;
      final onSplash = state.matchedLocation == Routes.splash;
      if (checking) return onSplash ? null : Routes.splash;
      return onSplash ? Routes.discover : null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: Routes.search, builder: (_, state) => SearchPage(author: state.uri.queryParameters['author'])),
      GoRoute(path: Routes.history, builder: (_, _) => const HistoryPage()),
      GoRoute(path: Routes.cache, builder: (_, _) => const CachePage()),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/novel/:aid', builder: (_, state) => NovelPageView(aid: state.pathParameters['aid']!)),
      GoRoute(path: '/novel/:aid/comments', builder: (_, state) => CommentsPage(aid: state.pathParameters['aid']!)),
      GoRoute(path: '/novel/:aid/comments/:rid', builder: (_, state) => RepliesPage(aid: state.pathParameters['aid']!, rid: state.pathParameters['rid']!)),
      GoRoute(path: '/reader/:aid/:cid', builder: (_, state) => ReaderPage(aid: state.pathParameters['aid']!, cid: state.pathParameters['cid']!)),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.discover, builder: (_, _) => const DiscoverPage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.bookshelf, builder: (_, _) => const BookshelfPage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfilePage())],
          ),
        ],
      ),
    ],
  );
});
