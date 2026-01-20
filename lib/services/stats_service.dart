import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';
import 'database_service.dart';

class StatsService {
  final http.Client _client;
  final String _sessionId;
  late final String _platform;
  bool _isSyncing = false;
  Timer? _syncTimer;

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

    // Periodically sync DBs back to server
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => _syncDbs());
  }

  String get sessionId => _sessionId;

  Future<void> track(
      String username, String songFilename, double duration, String eventType,
      {double foregroundDuration = 0.0,
      double backgroundDuration = 0.0,
      required double totalLength}) async {
    final payload = {
      'session_id': _sessionId,
      'song_filename': songFilename,
      'duration_played': duration,
      'event_type': eventType,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'platform': _platform,
      'foreground_duration': foregroundDuration,
      'background_duration': backgroundDuration,
      'total_length': totalLength,
      'play_ratio': totalLength > 0 ? duration / totalLength : 0.0,
    };

    // 1. Save locally to mirrored DB
    await DatabaseService.instance.insertPlayEvent(payload);

    // 2. Try to send to server (Legacy / Immediate)
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiService.baseUrl}/stats/track'),
            headers: {
              'Content-Type': 'application/json',
              'x-username': username,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Legacy stats tracking failed (Normal for local-first): $e');
    }
  }

  Future<void> _syncDbs() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('last_username');
      if (username != null) {
        await DatabaseService.instance.syncBack(username);
      }
    } catch (e) {
      debugPrint('DB Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<Map<String, dynamic>?> getStatsSummary(String username) async {
    // Mirroring final_stats.json locally
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File('${docDir.path}/${username}_final_stats.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content);
      }
    } catch (e) {
      debugPrint('Error reading local stats summary: $e');
    }

    // Fallback to API if local fails
    try {
      final response = await _client.get(
        Uri.parse('${ApiService.baseUrl}/user/shuffle'),
        headers: {
          'x-username': username,
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Stats summary error: $e');
    }
    return null;
  }

  Future<void> updateShuffleState(
      String username, Map<String, dynamic> state) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiService.baseUrl}/user/shuffle'),
            headers: {
              'Content-Type': 'application/json',
              'x-username': username,
            },
            body: jsonEncode(state),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Shuffle state update error (offline?): $e');
      // For shuffle state, we mostly rely on StorageService which already
      // persists it locally. The sync happens in AudioPlayerManager.
    }
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}
