import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'api_service.dart';

class StatsService {
  final http.Client _client;
  final String _sessionId;

  StatsService() 
      : _client = ApiService.createClient(),
        _sessionId = const Uuid().v4(); // Generate session ID on app launch

  String get sessionId => _sessionId;

  Future<void> track(String username, String songFilename, double duration, String eventType) async {
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
        }),
      );
    } catch (e) {
      // Silently fail stats to not disrupt UX
      print('Stats tracking error: $e');
    }
  }
}
