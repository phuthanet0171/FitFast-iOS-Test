import 'dart:async';

import 'package:http/http.dart' as http;

/// Gives up on a request that gets no response, e.g. on Wi-Fi without
/// internet. Every service already falls back to the copy saved on the
/// device when a request fails, so a timeout keeps the app usable offline
/// instead of showing a spinner until the system gives up.
///
/// Only the wait for the response headers is limited; a large download that
/// has started (such as the food catalogue) is not cut off.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 12),
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(timeout);

  @override
  void close() => _inner.close();
}
