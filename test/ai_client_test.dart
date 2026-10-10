import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frameforge/services/ai_client.dart';

class MemoryCredentials implements AiCredentialStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null) { values.remove(key); } else { values[key] = value; }
  }
}

http.Response capabilities() => http.Response(jsonEncode({'generation_mode': 'narrated_images', 'sign_in_configured': true,
  'planning_configured': true, 'generation_configured': true}), 200);

void main() {
  test('service URL accepts HTTPS and rejects credentials, insecure remote origins and paths', () {
    expect(AiClient.validateUrl('https://example.com/').toString(), 'https://example.com');
    expect(AiClient.validateUrl('http://127.0.0.1:8000').host, '127.0.0.1');
    for (final url in ['http://example.com', 'https://a:b@example.com', 'https://example.com/api', 'https://example.com?key=a']) {
      expect(() => AiClient.validateUrl(url), throwsA(isA<AiException>()));
    }
  });
  test('mobile login checks state and redeems a one-use code with its PKCE verifier', () async {
    final storage = MemoryCredentials();
    String? requestedChallenge;
    final client = AiClient(credentials: storage, browser: (url) async {
      final query = Uri.parse(url).queryParameters;
      requestedChallenge = query['device_challenge'];
      return Uri(scheme: 'frameforge-ai', host: 'login', queryParameters: {'state': query['device_state']!, 'code': 'c' * 43}).toString();
    }, httpClient: MockClient((request) async {
      if (request.url.path == '/api/capabilities') return capabilities();
      expect(request.url.path, '/api/session/exchange');
      expect(request.headers.containsKey('authorization'), false);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final challenge = base64UrlEncode(sha256.convert(ascii.encode(body['verifier'] as String)).bytes).replaceAll('=', '');
      expect(challenge, requestedChallenge);
      return http.Response(jsonEncode({'token': 't' * 64, 'user': {'id': 'a', 'name': 'Ada', 'email': null}}), 200);
    }));
    await client.connect('https://example.com'); await client.signIn();
    expect(client.account?.name, 'Ada'); expect(storage.values['ff_ai_session'], 't' * 64);
    client.close();
  });
  test('wrong callback state never exchanges credentials', () async {
    var exchanges = 0;
    final client = AiClient(credentials: MemoryCredentials(), browser: (_) async => 'frameforge-ai://login?state=attacker&code=${'c' * 43}',
      httpClient: MockClient((request) async { if (request.url.path != '/api/capabilities') exchanges++; return capabilities(); }));
    await client.connect('https://example.com');
    await expectLater(client.signIn(), throwsA(isA<AiException>()));
    expect(exchanges, 0); expect(client.account, null); client.close();
  });
  test('temporary service failures retain the session for reconnect', () async {
    final storage = MemoryCredentials()..values.addAll({'ff_ai_url': 'https://example.com', 'ff_ai_session': 't' * 64});
    final client = AiClient(credentials: storage, httpClient: MockClient((request) async =>
      request.url.path == '/api/capabilities' ? capabilities() : http.Response('{"detail":"Unavailable"}', 503)));
    await expectLater(client.restore(), throwsA(isA<AiException>()));
    expect(storage.values['ff_ai_session'], 't' * 64); client.close();
  });
  test('expired session is removed from secure storage', () async {
    final storage = MemoryCredentials()..values.addAll({'ff_ai_url': 'https://example.com', 'ff_ai_session': 't' * 64});
    final client = AiClient(credentials: storage, httpClient: MockClient((request) async =>
      request.url.path == '/api/capabilities' ? capabilities() : http.Response('{"detail":"Expired"}', 401)));
    await expectLater(client.restore(), throwsA(isA<AiException>()));
    expect(storage.values.containsKey('ff_ai_session'), false); client.close();
  });
  test('switching service clears the previous account session', () async {
    final storage = MemoryCredentials()..values.addAll({'ff_ai_url': 'https://old.example', 'ff_ai_session': 't' * 64});
    final client = AiClient(credentials: storage, httpClient: MockClient((request) async => request.url.path == '/api/capabilities' ? capabilities() :
      http.Response('{"user":{"id":"a","name":"Ada","email":null}}', 200)));
    await client.restore(); expect(client.account?.name, 'Ada');
    await client.connect('https://new.example');
    expect(client.account, null); expect(storage.values.containsKey('ff_ai_session'), false); client.close();
  });
  test('downloads stay on the service origin and never follow redirects with the session', () async {
    final storage = MemoryCredentials()..values.addAll({'ff_ai_url': 'https://example.com', 'ff_ai_session': 't' * 64});
    var downloads = 0;
    final client = AiClient(credentials: storage, httpClient: MockClient((request) async {
      if (request.url.path == '/api/capabilities') return capabilities();
      if (request.url.path == '/api/session') return http.Response('{"user":{"id":"a","name":"Ada","email":null}}', 200);
      downloads++; expect(request.followRedirects, false); expect(request.url.host, 'example.com');
      return http.Response('', 302, headers: {'location': 'https://other.example/private'});
    }));
    final temporary = await Directory.systemTemp.createTemp('ff_ai_redirect_');
    try {
      await client.restore();
      final file = File('${temporary.path}/video.mp4');
      await expectLater(client.download('a' * 32, 'video.mp4', file), throwsA(isA<AiException>()));
      expect(downloads, 1); expect(await file.exists(), false);
    } finally { client.close(); await temporary.delete(recursive: true); }
  });
  test('invalid asset paths are rejected before any network call', () async {
    final client = AiClient(credentials: MemoryCredentials(), httpClient: MockClient((_) async => throw StateError('Unexpected network request')));
    await expectLater(client.download('a' * 32, '../private', File('unused')), throwsA(isA<AiException>())); client.close();
  });
}
