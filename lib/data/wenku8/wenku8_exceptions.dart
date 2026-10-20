/// 数据层抛出的异常。界面层负责把它们翻译成给用户看的文字。
sealed class Wenku8Exception implements Exception {
  const Wenku8Exception(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 拿到的页面不是预期的结构：通常是未登录被跳到登录页、会话过期、
/// Cloudflare 验证页或节点不可用。
class Wenku8UnexpectedPageException extends Wenku8Exception {
  const Wenku8UnexpectedPageException(super.message);
}
