import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// 现在是不是 Wi-Fi（或有线）。查不出来就当是，免得一个限制让功能一直不工作。
Future<bool> onWifi() async {
  if (kIsWeb) return true;
  try {
    final c = await Connectivity().checkConnectivity();
    return c.contains(ConnectivityResult.wifi) || c.contains(ConnectivityResult.ethernet);
  } catch (_) {
    return true;
  }
}
