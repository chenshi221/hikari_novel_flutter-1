import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
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

  /// 最近一次成功取到的用户页 HTML，断网时用它显示登录状态。
  String? get userHtml => _box.get('userHtml') as String?;

  Future<void> setUserHtml(String html) => _box.put('userHtml', html);

  Future<void> setNode(Wenku8Node node) => _box.put('node', node.index);

  /// HTTP 代理（`127.0.0.1:7890`）。Dart 不会读系统代理，需要走代理的网络要在这里填。
  String get proxy => (_box.get('proxy') as String?) ?? '';

  Future<void> setProxy(String value) => _box.put('proxy', value.trim());

  /// 登录有效期（秒）。wenku8 不接受"临时登录"。
  int get keepSeconds => (_box.get('keepSeconds') as int?) ?? 2592000;

  Future<void> setKeepSeconds(int value) => _box.put('keepSeconds', value);

  /// 记住的账号密码，没记住时为 null。
  // shortcut: 明文存在本地 Hive，要更安全时改用 flutter_secure_storage（钥匙串 / Keystore）
  (String, String)? get savedLogin {
    final u = _box.get('savedUser') as String?;
    final p = _box.get('savedPass') as String?;
    return u == null || p == null ? null : (u, p);
  }

  Future<void> saveLogin(String? user, String? pass) async {
    if (user == null || pass == null) {
      await _box.delete('savedUser');
      await _box.delete('savedPass');
    } else {
      await _box.put('savedUser', user);
      await _box.put('savedPass', pass);
    }
  }
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
    dio: kIsWeb ? null : (Dio()..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => HttpClient()..findProxy = (_) => store.proxy.isEmpty ? 'DIRECT' : 'PROXY ${store.proxy}')),
  );
});

/// 图片专用的 Dio：和请求页面一样走所选代理，并带上浏览器 UA 和 Referer（图片服务器会检查）。
final imageDioProvider = Provider<Dio>((ref) {
  final store = ref.watch(sessionStoreProvider);
  return Dio(BaseOptions(responseType: ResponseType.bytes, headers: {...kUserAgent, 'Referer': '${siteBase(store)}/'}))
    ..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => HttpClient()..findProxy = (_) => store.proxy.isEmpty ? 'DIRECT' : 'PROXY ${store.proxy}');
});

final wenku8UrlsProvider = Provider<Wenku8Urls>((ref) => Wenku8Urls(siteBase(ref.watch(sessionStoreProvider)), CharsetType.gbk));

sealed class SessionState {
  const SessionState();
}

/// 启动时正在检查登录是否有效
class SessionChecking extends SessionState {
  const SessionChecking();
}

class SessionLoggedOut extends SessionState {
  const SessionLoggedOut({this.message});

  /// 给登录页显示的提示，例如"登录已过期"
  final String? message;
}

class SessionLoggedIn extends SessionState {
  const SessionLoggedIn(this.user, {this.offline = false});

  final UserInfo user;

  /// 没连上网站，用的是上次保存的账号信息；已缓存的内容仍可阅读
  final bool offline;
}

/// 登录状态。没登录也能进主界面（游客），需要账号的页面再提示登录。
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    Future.microtask(restore);
    return const SessionChecking();
  }

  SessionStore get _store => ref.read(sessionStoreProvider);

  Wenku8Client get _client => ref.read(wenku8ClientProvider);

  Wenku8Urls get _urls => ref.read(wenku8UrlsProvider);

  /// 启动时：有保存的登录信息就向网站确认一次。失效则清除；网络出错按游客处理，但保留 cookie，下次启动再检查。
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
    } catch (_) {
      // 联网失败不等于没登录：有 cookie 和上次保存的账号信息就按离线登录处理
      final html = _store.userHtml;
      state = html == null ? const SessionLoggedOut() : SessionLoggedIn(Wenku8Parser.userInfo(html), offline: true);
    }
  }

  /// 原生 App：在内嵌网页里登录后拿到的 cookie。
  Future<void> loginWithCookie(String cookie) async {
    await _client.clearCookie();
    await _client.restoreCookie(cookie, Wenku8Node.values.map((e) => e.node));
    await _confirm(cookie);
  }

  /// 网页预览：账号密码登录，由转发程序提交并保存 cookie。
  Future<void> loginWithPassword(String username, String password, int keepSeconds) async {
    await _client.clearCookie();
    await _client.postForm(_urls.loginSubmit(), _urls.loginForm(username, password, keepSeconds: keepSeconds));
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

  Future<UserInfo> _fetchUser() async {
    final html = await _client.getPage(_urls.userInfo());
    final user = Wenku8Parser.userInfo(html);
    await _store.setUserHtml(html);
    return user;
  }

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
