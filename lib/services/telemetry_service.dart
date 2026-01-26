import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';

class TelemetryService {
  static final TelemetryService instance = TelemetryService._internal();
  TelemetryService._internal();

  static const String _baseUrl = 'https://songs.gru0.dev/api/telemetry';
  static const String _appVersion = '3.4.2+1';

  final StorageService _storage = StorageService();

  String get _platform {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem;
  }

  Future<void> trackEvent(String eventName, Map<String, dynamic> data,
      {int requiredLevel = 1}) async {
    final currentLevel = await _storage.getTelemetryLevel();
    if (currentLevel < requiredLevel) return;

    await _sendTelemetry({
      'event': eventName,
      ...data,
    });
  }

  Future<void> trackFirstStartup(int level) async {
    final hasSent = await _storage.getHasSentFirstStartup();
    if (hasSent) return;

    await _sendTelemetry({
      'event': 'first_startup',
      'selected_level': level,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await _storage.setHasSentFirstStartup(true);
  }

  Future<void> _sendTelemetry(Map<String, dynamic> data) async {
    try {
      if (kIsWeb) return;

      final payload = {
        ...data,
        'platform': _platform,
        'timestamp':
            data['timestamp'] ?? DateTime.now().toUtc().toIso8601String(),
      };

      debugPrint('Sending telemetry: ${jsonEncode(payload)}');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final uri = Uri.parse(_baseUrl);
      final request = await client.postUrl(uri);

      request.headers.set('Content-Type', 'application/json');
      request.headers.set('User-Agent', 'GruSongs_$_appVersion');

      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close();

      // Read response body to ensure request is fully processed
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        debugPrint('Telemetry sent successfully: $responseBody');
      } else {
        debugPrint(
            'Failed to send telemetry: ${response.statusCode} - $responseBody');
      }
      client.close();
    } catch (e) {
      debugPrint('Error sending telemetry: $e');
    }
  }
}
