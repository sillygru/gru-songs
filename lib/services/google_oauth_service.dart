import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleOAuthService {
  static const String _clientId =
      '80722956975-niq9tgo5ia9s1k5in5m9ji7opn8j1akr.apps.googleusercontent.com';
  static const String _authEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String _scopes =
      'https://www.googleapis.com/auth/drive.appdata openid email';

  static const String _prefsKeyAccessToken = 'google_access_token';
  static const String _prefsKeyRefreshToken = 'google_refresh_token';
  static const String _prefsKeyTokenExpiry = 'google_token_expiry';
  static const String _prefsKeyAccountEmail = 'google_account_email';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  String? _accountEmail;
  String? _clientSecret;
  String? _lastError;

  http.Client? _client;

  bool get isSignedIn => _accessToken != null || _refreshToken != null;
  String? get accountEmail => _accountEmail;
  String? get lastError => _lastError;

  static final _random = Random.secure();

  void setClientSecret(String secret) {
    _clientSecret = secret;
  }

  http.Client _createDnsResilientClient() {
    final inner = HttpClient();
    inner.connectionFactory = (Uri url, String? host, int? port) async {
      InternetAddress addr;
      try {
        final addresses = await InternetAddress.lookup(
          url.host,
          type: InternetAddressType.IPv4,
        );
        if (addresses.isEmpty) {
          throw SocketException('No IPv4 address found for ${url.host}');
        }
        addr = addresses.first;
      } on SocketException {
        final fallback = await _resolveViaDnsOverUdp(url.host);
        if (fallback == null) rethrow;
        final rawTask = await Socket.startConnect(
          fallback.address,
          url.port,
        );
        final rawSocket = await rawTask.socket;
        final secureSocket = await SecureSocket.secure(
          rawSocket,
          host: url.host,
        );
        return ConnectionTask.fromSocket(
          Future.value(secureSocket),
          rawTask.cancel,
        );
      }
      if (url.scheme == 'https') {
        final secureTask = await SecureSocket.startConnect(addr, url.port);
        return ConnectionTask.fromSocket(
          secureTask.socket,
          secureTask.cancel,
        );
      }
      return await Socket.startConnect(addr, url.port);
    };
    return IOClient(inner);
  }

  Future<InternetAddress?> _resolveViaDnsOverUdp(String host) async {
    final queryId = _random.nextInt(65536);
    final query = _buildDnsQuery(host, queryId);

    for (final resolver in ['8.8.8.8', '1.1.1.1', '208.67.222.222']) {
      try {
        final result = await _dnsQuery(resolver, query, queryId);
        if (result != null) return InternetAddress(result);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static List<int> _buildDnsQuery(String host, int queryId) {
    final bytes = BytesBuilder();
    bytes.addByte((queryId >> 8) & 0xFF);
    bytes.addByte(queryId & 0xFF);
    bytes.addByte(0x01);
    bytes.addByte(0x00);
    bytes.addByte(0x00);
    bytes.addByte(0x01);
    bytes.addByte(0x00);
    bytes.addByte(0x00);
    bytes.addByte(0x00);
    bytes.addByte(0x00);
    bytes.addByte(0x00);
    bytes.addByte(0x00);

    for (final label in host.split('.')) {
      final encoded = utf8.encode(label);
      bytes.addByte(encoded.length);
      bytes.add(encoded);
    }
    bytes.addByte(0x00);
    bytes.addByte(0x00);
    bytes.addByte(0x01);
    bytes.addByte(0x00);
    bytes.addByte(0x01);

    return bytes.toBytes();
  }

  static String? _parseDnsResponse(List<int> data, int queryId) {
    if (data.length < 12) return null;
    if (((data[0] << 8) | data[1]) != queryId) return null;
    final flags = (data[2] << 8) | data[3];
    if ((flags & 0x8000) == 0) return null;
    if ((flags & 0x000F) != 0) return null;

    final answerCount = (data[6] << 8) | data[7];
    if (answerCount < 1) return null;

    int offset = 12;
    while (offset < data.length && data[offset] != 0) {
      offset += data[offset] + 1;
    }
    offset += 5;

    for (int i = 0; i < answerCount; i++) {
      if (offset + 2 > data.length) break;
      if ((data[offset] & 0xC0) == 0xC0) {
        offset += 2;
      } else {
        while (offset < data.length && data[offset] != 0) {
          offset += data[offset] + 1;
        }
        offset++;
      }

      if (offset + 10 > data.length) break;
      final type = (data[offset] << 8) | data[offset + 1];
      final cls = (data[offset + 2] << 8) | data[offset + 3];
      offset += 8;
      final rdlength = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      if (type == 1 && cls == 1 && rdlength == 4 && offset + 4 <= data.length) {
        return '${data[offset]}.${data[offset + 1]}.${data[offset + 2]}.${data[offset + 3]}';
      }
      offset += rdlength;
    }
    return null;
  }

  Future<String?> _dnsQuery(
    String resolver,
    List<int> query,
    int queryId,
  ) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final completer = Completer<String?>();
    StreamSubscription? sub;

    sub = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null && !completer.isCompleted) {
          final addr = _parseDnsResponse(datagram.data, queryId);
          if (addr != null) completer.complete(addr);
        }
      }
    });

    Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) completer.complete(null);
    });

    try {
      socket.send(query, InternetAddress(resolver), 53);
      return await completer.future;
    } finally {
      await sub.cancel();
      socket.close();
    }
  }

  Future<void> init() async {
    _client = _createDnsResilientClient();

    const envSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');
    if (envSecret.isNotEmpty) {
      _clientSecret = envSecret;
    } else {
      _clientSecret = Platform.environment['GOOGLE_CLIENT_SECRET'];
    }

    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_prefsKeyAccessToken);
    _refreshToken = prefs.getString(_prefsKeyRefreshToken);
    _accountEmail = prefs.getString(_prefsKeyAccountEmail);
    final expiry = prefs.getInt(_prefsKeyTokenExpiry);
    if (expiry != null) {
      _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(expiry);
    }

    if (_accessToken != null &&
        _refreshToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isAfter(_tokenExpiry!)) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        debugPrint('GoogleOAuthService: silent token refresh failed');
      }
    }
  }

  Future<bool> signIn() async {
    try {
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);
      final state = _generateState();

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      final redirectUri = 'http://127.0.0.1:$port';

      final authUri = Uri.parse(_authEndpoint).replace(queryParameters: {
        'response_type': 'code',
        'client_id': _clientId,
        'redirect_uri': redirectUri,
        'scope': _scopes,
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
      });

      if (!await launchUrl(authUri, mode: LaunchMode.platformDefault)) {
        await server.close();
        _lastError = 'Failed to open browser';
        return false;
      }

      final request = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          unawaited(server.close());
          throw TimeoutException('OAuth sign-in timed out after 5 minutes');
        },
      );
      final receivedState = request.uri.queryParameters['state'];
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];

      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!DOCTYPE html><html><body>'
        '<p>Authentication complete. You can close this tab.</p>'
        '</body></html>',
      );
      await request.response.close();
      await server.close();

      if (error != null) {
        debugPrint('GoogleOAuthService: OAuth error: $error');
        return false;
      }

      if (receivedState != state) {
        debugPrint('GoogleOAuthService: state mismatch');
        return false;
      }

      if (code == null) {
        debugPrint('GoogleOAuthService: no authorization code in redirect');
        return false;
      }

      await _exchangeCodeForTokens(code, codeVerifier, redirectUri);
      _lastError = null;
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('GoogleOAuthService: sign-in failed: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
    _accountEmail = null;
    _lastError = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyAccessToken);
    await prefs.remove(_prefsKeyRefreshToken);
    await prefs.remove(_prefsKeyTokenExpiry);
    await prefs.remove(_prefsKeyAccountEmail);
  }

  Future<Map<String, String>> get authHeaders async {
    if (_accessToken == null) {
      throw StateError('GoogleOAuthService: not authenticated');
    }

    if (_tokenExpiry != null &&
        DateTime.now()
            .isAfter(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      if (_refreshToken != null) {
        final refreshed = await _refreshAccessToken();
        if (!refreshed) {
          throw StateError('GoogleOAuthService: token refresh failed');
        }
      } else {
        throw StateError('GoogleOAuthService: token expired, no refresh token');
      }
    }

    return {'Authorization': 'Bearer $_accessToken'};
  }

  Future<void> _exchangeCodeForTokens(
    String code,
    String codeVerifier,
    String redirectUri,
  ) async {
    final client = _client ?? http.Client();
    final tokenBody = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': _clientId,
      'code_verifier': codeVerifier,
    };
    if (_clientSecret != null) {
      tokenBody['client_secret'] = _clientSecret!;
    }

    final response = await client.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: tokenBody,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Token exchange failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _storeTokens(data);
  }

  Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final client = _client ?? http.Client();
      final refreshBody = <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
        'client_id': _clientId,
      };
      if (_clientSecret != null) {
        refreshBody['client_secret'] = _clientSecret!;
      }

      final response = await client.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: refreshBody,
      );

      if (response.statusCode != 200) {
        debugPrint(
          'GoogleOAuthService: refresh failed (${response.statusCode}): ${response.body}',
        );
        await signOut();
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await _storeTokens(data);
      return true;
    } catch (e) {
      debugPrint('GoogleOAuthService: token refresh error: $e');
      return false;
    }
  }

  Future<void> _storeTokens(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    final accessToken = data['access_token'] as String?;
    if (accessToken != null) {
      _accessToken = accessToken;
      await prefs.setString(_prefsKeyAccessToken, accessToken);
    }

    final refreshToken = data['refresh_token'] as String?;
    if (refreshToken != null) {
      _refreshToken = refreshToken;
      await prefs.setString(_prefsKeyRefreshToken, refreshToken);
    }

    final expiresIn = data['expires_in'] as int? ?? 3600;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
    await prefs.setInt(
        _prefsKeyTokenExpiry, _tokenExpiry!.millisecondsSinceEpoch);

    final idToken = data['id_token'] as String?;
    if (idToken != null) {
      final email = _extractEmailFromIdToken(idToken);
      if (email != null) {
        _accountEmail = email;
        await prefs.setString(_prefsKeyAccountEmail, email);
      }
    }
  }

  static String _generateCodeVerifier() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _generateCodeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static String _generateState() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String? _extractEmailFromIdToken(String idToken) {
    final parts = idToken.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = base64Url.decode(_padBase64(parts[1]));
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      return json['email'] as String?;
    } catch (e) {
      debugPrint('GoogleOAuthService: failed to decode id_token: $e');
      return null;
    }
  }

  static String _padBase64(String input) {
    final remainder = input.length % 4;
    if (remainder == 0) return input;
    return input + '=' * (4 - remainder);
  }
}
