import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'database_service.dart';

class StatsService {
  final String _sessionId;
  late final String _platform;
  final List<Map<String, dynamic>> _pendingStats = [];
  bool _isBackground = false;
  Future<bool>? _activeFlush;

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

    _pendingStats.add(statsWithMeta);

    if (!_isBackground || _pendingStats.length >= 50) {
      await flush();
    }
  }

  Future<void> syncBack() async {
    // Local-only - no sync needed
  }

  Future<void> flush() async {
    while (true) {
      final activeFlush = _activeFlush;
      if (activeFlush != null) {
        final success = await activeFlush;
        if (!success || _pendingStats.isEmpty) return;
        continue;
      }

      if (_pendingStats.isEmpty) return;

      final future = _flushPending();
      _activeFlush = future;
      bool success = false;
      try {
        success = await future;
      } finally {
        if (identical(_activeFlush, future)) {
          _activeFlush = null;
        }
      }

      if (!success || _pendingStats.isEmpty) return;
    }
  }

  Future<bool> _flushPending() async {
    while (_pendingStats.isNotEmpty) {
      final batch = List<Map<String, dynamic>>.from(_pendingStats);

      try {
        await DatabaseService.instance.init();
        await DatabaseService.instance.insertPlayEventsBatch(batch);
        _pendingStats.removeRange(0, batch.length);
        debugPrint('Flushed ${batch.length} batched stats events.');
      } catch (e) {
        debugPrint('Error flushing stats batch: $e');
        return false;
      }
    }
    return true;
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
