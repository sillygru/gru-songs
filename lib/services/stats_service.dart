import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

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
    
    // Periodically try to sync offline stats
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => _flushOfflineStats());
  }

  String get sessionId => _sessionId;

  Future<void> track(String username, String songFilename, double duration, String eventType, {double foregroundDuration = 0.0, double backgroundDuration = 0.0}) async {
    final payload = {
      'session_id': _sessionId,
      'song_filename': songFilename,
      'duration_played': duration,
      'event_type': eventType,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'platform': _platform,
      'foreground_duration': foregroundDuration,
      'background_duration': backgroundDuration,
    };

    try {
      final response = await _client.post(
        Uri.parse('${ApiService.baseUrl}/stats/track'),
        headers: {
          'Content-Type': 'application/json',
          'x-username': username,
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }
      
      // If we succeed, also try to flush any previously cached stats
      _flushOfflineStats();
      
    } catch (e) {
      debugPrint('Stats tracking failed, caching for later: $e');
      _cacheStatsOffline(username, payload);
    }
  }

  Future<void> _cacheStatsOffline(String username, Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'offline_stats_$username';
      List<String> cached = prefs.getStringList(key) ?? [];
      cached.add(jsonEncode(payload));
      await prefs.setStringList(key, cached);
    } catch (e) {
      debugPrint('Failed to cache stats offline: $e');
    }
  }

  Future<void> _flushOfflineStats() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      // We need to know which users have offline stats. Since we usually only have one active user:
      final keys = prefs.getKeys().where((k) => k.startsWith('offline_stats_')).toList();
      
      for (final key in keys) {
        final username = key.replaceFirst('offline_stats_', '');
        List<String> cached = prefs.getStringList(key) ?? [];
        if (cached.isEmpty) continue;

        debugPrint('Syncing ${cached.length} offline stats for $username...');
        List<String> remaining = [];
        bool stopSync = false;

        for (final itemJson in cached) {
          if (stopSync) {
            remaining.add(itemJson);
            continue;
          }

          try {
            final response = await _client.post(
              Uri.parse('${ApiService.baseUrl}/stats/track'),
              headers: {
                'Content-Type': 'application/json',
                'x-username': username,
              },
              body: itemJson,
            ).timeout(const Duration(seconds: 10));

            if (response.statusCode != 200) {
              stopSync = true;
              remaining.add(itemJson);
            }
          } catch (e) {
            stopSync = true;
            remaining.add(itemJson);
          }
        }

        await prefs.setStringList(key, remaining);
        if (remaining.isEmpty) {
          debugPrint('All offline stats synced for $username');
        }
      }
    } catch (e) {
      debugPrint('Error during offline stats flush: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<Map<String, dynamic>?> getStatsSummary(String username) async {
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
      debugPrint('Stats summary error (offline?): $e');
    }
    return null;
  }

  Future<void> updateShuffleState(String username, Map<String, dynamic> state) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiService.baseUrl}/user/shuffle'),
        headers: {
          'Content-Type': 'application/json',
          'x-username': username,
        },
        body: jsonEncode(state),
      ).timeout(const Duration(seconds: 5));
      
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