import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

class StatsService {
  final String _sessionId;
  late final String _platform;
  final List<Map<String, dynamic>> _pendingStats = [];
  bool _isBackground = false;

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

  void setBackground(bool value) {
    _isBackground = value;
    if (!value) {
      // Immediately flush when coming back to foreground
      flush();
    }
  }

  Future<void> trackStats(Map<String, dynamic> stats) async {
    final statsWithMeta = Map<String, dynamic>.from(stats);
    statsWithMeta['platform'] = _platform;
    statsWithMeta['session_id'] = _sessionId;
    statsWithMeta['timestamp'] = DateTime.now().millisecondsSinceEpoch / 1000.0;

    if (_isBackground) {
      _pendingStats.add(statsWithMeta);
      // Limit the buffer size to maintain a low memory footprint.
      if (_pendingStats.length >= 50) {
        await flush();
      }
    } else {
      // In foreground mode, commit stats immediately to provide real-time updates.
      if (_pendingStats.isNotEmpty) {
        await flush();
      }
      await _writeSingle(statsWithMeta);
    }
  }

  Future<void> _writeSingle(Map<String, dynamic> event) async {
    try {
      await DatabaseService.instance.init();
      await DatabaseService.instance.insertPlayEvent(event);
    } catch (e) {
      debugPrint('Error writing single stat: $e');
    }
  }

  Future<void> syncBack() async {
    // Local-only - no sync needed
  }

  Future<void> flush() async {
    if (_pendingStats.isEmpty) return;

    final batch = List<Map<String, dynamic>>.from(_pendingStats);
    _pendingStats.clear();

    try {
      await DatabaseService.instance.init();
      await DatabaseService.instance.insertPlayEventsBatch(batch);

      debugPrint('Flushed ${batch.length} batched stats events.');
    } catch (e) {
      debugPrint('Error flushing stats batch: $e');
    }
  }

  void dispose() {
    flush(); // Final flush on dispose
  }

  Future<Map<String, dynamic>> getFunStats() async {
    // Get stats from local database
    try {
      await DatabaseService.instance.init();
      return await DatabaseService.instance.getFunStats();
    } catch (e) {
      debugPrint('Error getting fun stats: $e');
      return {};
    }
  }
}
