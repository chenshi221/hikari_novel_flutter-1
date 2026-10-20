import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/bookshelf_page.dart';
import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'pages/profile_page.dart';
import 'pages/splash_page.dart';
import 'session.dart';

class Routes {
  const Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const bookshelf = '/bookshelf';
  static const profile = '/profile';
}

/// 路由统一按登录状态拦截：检查中 → 启动页；未登录 → 登录页；已登录才能进主界面。
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<SessionState>(ref.read(sessionProvider));
  ref.listen(sessionProvider, (_, next) => refresh.value = next);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final location = state.matchedLocation;
      return switch (ref.read(sessionProvider)) {
        SessionChecking() || SessionCheckFailed() => location == Routes.splash ? null : Routes.splash,
        SessionLoggedOut() => location == Routes.login ? null : Routes.login,
        SessionLoggedIn() => (location == Routes.login || location == Routes.splash) ? Routes.bookshelf : null,
      };
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
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
