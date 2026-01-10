import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'api_service.dart';

class StatsService {
  final http.Client _client;
  final String _sessionId;
  late final String _platform;

  StatsService() 
      : _client = ApiService.createClient(),
        _sessionId = const Uuid().v4() {
    if (kIsWeb) {
      _platform = 'web';
    } else if (Platform.isAndroid) {
      _platform = 'android';
    } else if (Platform.isIOS) {
      _platform = 'ios';
    } else if (Platform.isMacOS) {
      _platform = 'macos';
    } else if (Platform.isWindows) {
      _platform = 'windows';
    } else if (Platform.isLinux) {
      _platform = 'linux';
    } else if (Platform.isFuchsia) {
      _platform = 'fuchsia';
    } else {
      _platform = 'unknown';
    }
  }

  String get sessionId => _sessionId;

  Future<void> track(String username, String songFilename, double duration, String eventType, {double foregroundDuration = 0.0, double backgroundDuration = 0.0}) async {
    try {
      await _client.post(
        Uri.parse('${ApiService.baseUrl}/stats/track'),
        headers: {
          'Content-Type': 'application/json',
          'x-username': username,
        },
        body: jsonEncode({
          'session_id': _sessionId,
          'song_filename': songFilename,
          'duration_played': duration,
          'event_type': eventType,
          'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
          'platform': _platform,
          'foreground_duration': foregroundDuration,
          'background_duration': backgroundDuration,
        }),
      );
    } catch (e) {
      // Silently fail stats to not disrupt UX
      print('Stats tracking error: $e');
    }
  }
}
