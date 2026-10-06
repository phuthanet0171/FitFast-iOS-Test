import 'dart:async';

import 'package:fitfast/services/timeout_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('a request without a response fails instead of waiting forever',
      () async {
    final never = Completer<http.Response>();
    final client = TimeoutHttpClient(
      inner: MockClient((_) => never.future),
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(client.get(Uri.parse('https://example.com')),
        throwsA(isA<TimeoutException>()));
  });

  test('a normal response passes through', () async {
    final client = TimeoutHttpClient(
      inner: MockClient((_) async => http.Response('ok', 200)),
    );
    final response = await client.get(Uri.parse('https://example.com'));
    expect(response.body, 'ok');
  });
}
