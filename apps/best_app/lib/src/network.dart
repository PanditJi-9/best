import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the queue needs to know about the connection, and nothing more.
///
/// `unknown` is a first-class answer: a platform without the plugin, a VPN, or
/// a permission the person declined. Unknown never blocks a download, because
/// guessing "metered" would silently stop the app.
enum NetworkKind { wifi, mobile, none, unknown }

NetworkKind networkKindOf(List<ConnectivityResult> results) {
  if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
    return NetworkKind.none;
  }
  if (results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet)) {
    return NetworkKind.wifi;
  }
  if (results.contains(ConnectivityResult.mobile)) return NetworkKind.mobile;
  return NetworkKind.unknown;
}

final StreamProvider<NetworkKind> networkProvider =
    StreamProvider<NetworkKind>((ref) async* {
  final connectivity = Connectivity();
  try {
    yield networkKindOf(await connectivity.checkConnectivity());
  } catch (_) {
    yield NetworkKind.unknown;
  }
  try {
    yield* connectivity.onConnectivityChanged.map(networkKindOf);
  } catch (_) {
    // The stream is an optimisation; the first value already stands.
  }
});
