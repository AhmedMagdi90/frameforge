import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import '../models/ai_video.dart';
import '../models/project.dart';

class AiException implements Exception {
  const AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class AiCredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureAiCredentialStore implements AiCredentialStore {
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String? value) => value == null
    ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

typedef AiBrowserLogin = Future<String> Function(String url);

class AiClient {
  AiClient({http.Client? httpClient, AiCredentialStore? credentials, AiBrowserLogin? browser})
      : _http = httpClient ?? http.Client(), _credentials = credentials ?? SecureAiCredentialStore(),
        _browser = browser ?? ((url) => FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: 'frameforge-ai'));
  final http.Client _http;
  final AiCredentialStore _credentials;
  final AiBrowserLogin _browser;
  Uri? _base;
  String? _token;
  AiAccount? account;
  Map<String, dynamic> capabilities = {};
  String get serviceUrl => _base?.toString() ?? '';
  bool get configured => _base != null;
  static String requestKey() => base64UrlEncode(List<int>.generate(48, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
  static Uri validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') || (uri.scheme != 'https' &&
          !(uri.scheme == 'http' && ['localhost', '127.0.0.1', '::1'].contains(uri.host)))) {
      throw const AiException('Enter the HTTPS address of your AI service.');
    }
    return uri.replace(path: '');
  }
  Future<void> restore() async {
    final saved = await _credentials.read('ff_ai_url');
    const builtIn = String.fromEnvironment('FRAMEFORGE_AI_URL');
    final value = saved ?? builtIn;
    if (value.isEmpty) return;
    _base = validateUrl(value);
    _token = await _credentials.read('ff_ai_session');
    await refresh();
  }
  Future<void> connect(String value) async {
    final candidate = validateUrl(value);
    // Probe before discarding an existing service/session.
    final request = http.Request('GET', candidate.resolve('/api/capabilities'))..followRedirects = false;
    final response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 20)));
    final result = _decode(response);
    if (result['generation_mode'] != 'narrated_images') throw const AiException('This is not a compatible FrameForge AI service.');
    if (_base != candidate) {
      await _credentials.write('ff_ai_session', null);
      _token = null; account = null;
    }
    _base = candidate; capabilities = result;
    await _credentials.write('ff_ai_url', candidate.toString());
  }
  Future<void> refresh() async {
    capabilities = await _request('GET', '/api/capabilities', authenticated: false);
    if (_token != null) account = AiAccount.fromJson(aiMap((await _request('GET', '/api/session'))['user']));
  }
  Future<void> signIn() async {
    if (_base == null) throw const AiException('Connect your AI service first.');
    final verifier = requestKey(), state = requestKey();
    final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final start = _base!.resolve('/auth/openai/start').replace(queryParameters: {'device_challenge': challenge, 'device_state': state});
    String result;
    try { result = await _browser(start.toString()); }
    on PlatformException catch (error) {
      throw AiException(['CANCELED', 'CANCELLED'].contains(error.code.toUpperCase())
        ? 'Sign-in was cancelled.' : 'Could not open ChatGPT sign-in. Try again.');
    }
    final callback = Uri.parse(result);
    if (callback.scheme != 'frameforge-ai' || callback.host != 'login' ||
        callback.path.isNotEmpty || callback.queryParameters['state'] != state ||
        callback.queryParametersAll['state']?.length != 1) {
      throw const AiException('Sign-in could not be verified. Try again.');
    }
    if (callback.queryParameters.containsKey('error')) throw const AiException('ChatGPT sign-in did not complete. Try again.');
    final code = callback.queryParameters['code'];
    if (code == null || !RegExp(r'^[A-Za-z0-9_-]{30,100}$').hasMatch(code)) throw const AiException('Invalid sign-in response.');
    final response = await _request('POST', '/api/session/exchange', authenticated: false, body: {'code': code, 'verifier': verifier});
    final token = response['token'];
    final user = AiAccount.fromJson(aiMap(response['user']));
    if (token is! String || !RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(token)) throw const AiException('Invalid app session.');
    await _credentials.write('ff_ai_session', token);
    _token = token; account = user;
  }
  Future<void> signOut() async {
    try { if (_token != null) await _request('DELETE', '/api/session'); }
    finally { _token = null; account = null; await _credentials.write('ff_ai_session', null); }
  }
  Future<AiVideoPlan> plan(List<Map<String, String>> messages, CanvasRatio ratio, int seconds) async =>
    AiVideoPlan.fromJson(await _request('POST', '/api/ideas/plan', body: {'messages': messages, 'ratio': ratio.name, 'seconds': seconds},
      timeout: const Duration(minutes: 2)));
  Future<AiJob> generate(AiVideoPlan plan, String voice, String key) async => AiJob.fromJson(
    await _request('POST', '/api/jobs', body: {'plan': plan.toJson(), 'voice': voice, 'request_key': key}));
  Future<List<AiJob>> jobs() async {
    final result = (await _request('GET', '/api/jobs'))['jobs'];
    if (result is! List) throw const FormatException('Invalid video history');
    return result.map((value) => AiJob.fromJson(aiMap(value))).toList();
  }
  Future<AiJob> job(String id) async => AiJob.fromJson(await _request('GET', '/api/jobs/${_jobId(id)}'));
  Future<AiJob> cancel(String id) async => AiJob.fromJson(await _request('DELETE', '/api/jobs/${_jobId(id)}'));
  String _jobId(String id) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) throw const AiException('Invalid video identifier.');
    return id;
  }
  Future<void> download(String jobId, String filename, File destination) async {
    if (!RegExp(r'^(video|scene0[1-6])\.mp4$').hasMatch(filename)) throw const AiException('Invalid video asset.');
    final uri = _uri('/api/jobs/${_jobId(jobId)}/assets/$filename');
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers.addAll(_headers(true));
    IOSink? sink;
    try {
      final response = await _http.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        if (response.statusCode == 401) await _expired();
        throw const AiException('The generated video could not be downloaded. Retry from your video history.');
      }
      const maximum = 500 * 1024 * 1024;
      if ((response.contentLength ?? 0) > maximum) throw const AiException('The video exceeds the download limit.');
      sink = destination.openWrite();
      var length = 0;
      await for (final chunk in response.stream.timeout(const Duration(seconds: 45))) {
        length += chunk.length;
        if (length > maximum) throw const AiException('The video exceeds the download limit.');
        sink.add(chunk);
        // Apply disk backpressure instead of retaining the entire video in memory.
        await sink.flush();
      }
      await sink.close(); sink = null;
      if (length < 100 || (response.contentLength != null && length != response.contentLength)) {
        throw const AiException('The video download was incomplete.');
      }
    } catch (_) {
      if (sink != null) { try { await sink.close(); } catch (_) {} }
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }
  Uri _uri(String path) {
    if (_base == null) throw const AiException('Connect your AI service first.');
    return _base!.resolve(path);
  }
  Map<String, String> _headers(bool authenticated) {
    if (authenticated && _token == null) throw const AiException('Sign in with ChatGPT first.');
    return {'Accept': 'application/json', if (authenticated) 'Authorization': 'Bearer $_token'};
  }
  Future<void> _expired() async {
    _token = null; account = null; await _credentials.write('ff_ai_session', null);
  }
  Future<Map<String, dynamic>> _request(String method, String path, {Object? body, bool authenticated = true,
    Duration timeout = const Duration(seconds: 30)}) async {
    try {
      final request = http.Request(method, _uri(path))..followRedirects = false;
      request.headers.addAll(_headers(authenticated));
      if (body != null) { request.headers['Content-Type'] = 'application/json'; request.body = jsonEncode(body); }
      final response = await http.Response.fromStream(await _http.send(request).timeout(timeout)).timeout(timeout);
      if (response.statusCode == 401 && authenticated) await _expired();
      return _decode(response);
    } on TimeoutException { throw const AiException('The AI service took too long. Retry or check your video history.'); }
    on http.ClientException { throw const AiException('Could not reach your AI service. Check your connection.'); }
    on SocketException { throw const AiException('Could not reach your AI service. Check your connection.'); }
  }
  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> result;
    try { result = aiMap(jsonDecode(response.body)); }
    catch (_) { throw const AiException('The AI service returned an unreadable response.'); }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = result['detail'];
      throw AiException(detail is String && detail.length <= 1000 ? detail : 'The AI service could not complete this request.');
    }
    return result;
  }
  void close() => _http.close();
}
