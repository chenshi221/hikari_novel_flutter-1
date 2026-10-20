import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../common/constants.dart';
import '../data/wenku8/wenku8_client.dart';
import '../data/wenku8/wenku8_exceptions.dart';
import '../data/wenku8/wenku8_parser.dart';
import '../data/wenku8/wenku8_urls.dart';
import '../models/common/charset_type.dart';
import '../models/common/wenku8_node.dart';
import '../models/user_info.dart';
import 'env.dart';

/// 本地保存的登录信息：cookie 和选择的节点。
class SessionStore {
  SessionStore._(this._box);

  final Box _box;

  static Future<SessionStore> open() async {
    await Hive.initFlutter('next');
    return SessionStore._(await Hive.openBox('session'));
  }

  /// 原生 App：wenku8 的 cookie 字符串；网页预览：cookie 保存在转发程序里，这里只存一个标记。
  String? get cookie => _box.get('cookie') as String?;

  Future<void> setCookie(String? value) => value == null ? _box.delete('cookie') : _box.put('cookie', value);

  Wenku8Node get node => Wenku8Node.values[(_box.get('node') as int?) ?? Wenku8Node.wwwWenku8Net.index];

  Future<void> setNode(Wenku8Node node) => _box.put('node', node.index);
}

final sessionStoreProvider = Provider<SessionStore>((ref) => throw UnimplementedError('在 main() 里通过 overrides 提供'));

/// 当前用于请求的站点地址：网页预览走转发程序，原生 App 直连所选节点。
String siteBase(SessionStore store) => isWebPreview ? previewProxyBase : store.node.node;

final wenku8ClientProvider = Provider<Wenku8Client>((ref) {
  final store = ref.watch(sessionStoreProvider);
  return Wenku8Client(
    baseUrl: () => siteBase(store),
    charset: () => CharsetType.gbk,
    // 浏览器不允许网页设置 User-Agent，由转发程序代为添加
    headers: kIsWeb ? const {} : kUserAgent,
  );
});

final wenku8UrlsProvider = Provider<Wenku8Urls>((ref) => Wenku8Urls(siteBase(ref.watch(sessionStoreProvider)), CharsetType.gbk));

sealed class SessionState {
  const SessionState();
}

/// 启动时正在检查登录是否有效
class SessionChecking extends SessionState {
  const SessionChecking();
}

/// 检查时出了网络等问题，不确定登录是否还有效
class SessionCheckFailed extends SessionState {
  const SessionCheckFailed(this.message);

  final String message;
}

class SessionLoggedOut extends SessionState {
  const SessionLoggedOut({this.message});

  /// 给登录页显示的提示，例如"登录已过期"
  final String? message;
}

class SessionLoggedIn extends SessionState {
  const SessionLoggedIn(this.user);

  final UserInfo user;
}

/// 登录状态。路由根据它决定显示启动页、登录页还是主界面：没登录就进不了主界面。
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    Future.microtask(restore);
    return const SessionChecking();
  }

  SessionStore get _store => ref.read(sessionStoreProvider);

  Wenku8Client get _client => ref.read(wenku8ClientProvider);

  Wenku8Urls get _urls => ref.read(wenku8UrlsProvider);

  /// 启动时：有保存的登录信息就向网站确认一次，失效则回到登录页。
  Future<void> restore() async {
    final cookie = _store.cookie;
    if (cookie == null) {
      state = const SessionLoggedOut();
      return;
    }
    state = const SessionChecking();
    if (!isWebPreview) await _client.restoreCookie(cookie, Wenku8Node.values.map((e) => e.node));
    try {
      state = SessionLoggedIn(await _fetchUser());
    } on Wenku8UnexpectedPageException {
      await _clear();
      state = const SessionLoggedOut(message: '登录已过期，请重新登录');
    } catch (e) {
      state = SessionCheckFailed(e.toString());
    }
  }

  /// 原生 App：在内嵌网页里登录后拿到的 cookie。
  Future<void> loginWithCookie(String cookie) async {
    await _client.clearCookie();
    await _client.restoreCookie(cookie, Wenku8Node.values.map((e) => e.node));
    await _confirm(cookie);
  }

  /// 网页预览：账号密码登录，由转发程序提交并保存 cookie。
  Future<void> loginWithPassword(String username, String password) async {
    await _client.postForm(_urls.loginSubmit(), _urls.loginForm(username, password));
    await _confirm('preview');
  }

  Future<void> _confirm(String cookie) async {
    try {
      final user = await _fetchUser();
      await _store.setCookie(cookie);
      state = SessionLoggedIn(user);
    } on Wenku8UnexpectedPageException {
      await _clear();
      throw const Wenku8UnexpectedPageException('登录失败：账号或密码不对，或者选择了"临时登录"');
    }
  }

  Future<UserInfo> _fetchUser() async => Wenku8Parser.userInfo(await _client.getPage(_urls.userInfo()));

  Future<void> logout() async {
    if (isWebPreview) {
      try {
        await _client.dio.post('$previewProxyBase/__session/logout');
      } catch (_) {}
    }
    await _clear();
    state = const SessionLoggedOut();
  }

  Future<void> _clear() async {
    await _store.setCookie(null);
    await _client.clearCookie();
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);
