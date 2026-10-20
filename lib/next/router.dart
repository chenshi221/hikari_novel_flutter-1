import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/bookshelf_page.dart';
import 'pages/discover_page.dart';
import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'pages/profile_page.dart';
import 'pages/splash_page.dart';
import 'session.dart';

class Routes {
  const Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const discover = '/discover';
  static const bookshelf = '/bookshelf';
  static const profile = '/profile';
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
