import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

class StatsService {
  final String _sessionId;
  late final String _platform;

  StatsService() : _sessionId = const Uuid().v4() {
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
    } else {
      _platform = 'unknown';
    }
  }

  Future<void> trackStats(Map<String, dynamic> stats) async {
    // Local-only - just store in database
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      if (username == null) return;

      await DatabaseService.instance.initForUser(username);

      // Add platform info
      stats['platform'] = _platform;
      stats['session_id'] = _sessionId;

      // Store in local database
      await DatabaseService.instance.addPlayEvent(stats);
    } catch (e) {
      debugPrint('Error tracking stats: $e');
    }
  }

  Future<void> syncBack() async {
    // Local-only - no sync needed
  }

  Future<void> flush() async {
    // Local-only - data is already in database
  }

  Future<Map<String, dynamic>> getFunStats() async {
    // Get stats from local database
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      if (username == null) return {};

      await DatabaseService.instance.initForUser(username);
      return await DatabaseService.instance.getFunStats();
    } catch (e) {
      debugPrint('Error getting fun stats: $e');
      return {};
    }
  }
}
