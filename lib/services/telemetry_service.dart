import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'storage_service.dart';

class TelemetryService {
  static final TelemetryService instance = TelemetryService._internal();
  TelemetryService._internal();

  static const String _projectId = 'wispie';
  static const String _baseUrl = 'https://api.gru0.dev/telemetry/api/v1/event';
  static const String _secret = String.fromEnvironment('TELEMETRY_SECRET');

  String? _uuid;
  PackageInfo? _packageInfo;

  bool get _isSecretSet => _secret.isNotEmpty;

  Future<String> get _appVersion async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!.version;
  }

  Future<String> _getOrCreateUuid() async {
    if (_uuid != null) return _uuid!;

    final prefs = await SharedPreferences.getInstance();
    _uuid = prefs.getString('telemetry_id');

    if (_uuid == null || _uuid!.isEmpty) {
      _uuid = const Uuid().v4();
      await prefs.setString('telemetry_id', _uuid!);
    }

    return _uuid!;
  }

  String _computeSig(String uuid, String secret) {
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final message = '$_projectId:$uuid:$today';
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(message));
    return digest.toString();
  }

  Future<Map<String, dynamic>> _buildBasePayload() async {
    final uuid = await _getOrCreateUuid();
    final version = await _appVersion;
    final sig = _computeSig(uuid, _secret);

    return {
      'uuid': uuid,
      'project_id': _projectId,
      'version': version,
      'sig': sig,
    };
  }

  void _send(Map<String, dynamic> payload) {
    unawaited(_doSend(payload));
  }

  Future<void> _doSend(Map<String, dynamic> payload) async {
    if (!_isSecretSet) return;

    try {
      if (kIsWeb) return;

      debugPrint('Sending telemetry: ${jsonEncode(payload)}');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final uri = Uri.parse(_baseUrl);
      final request = await client.postUrl(uri);

      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close();
      await response.transform(utf8.decoder).join();
      client.close();
    } catch (e) {
      debugPrint('Telemetry error: $e');
    }
  }

  Future<void> reportLaunch() async {
    final storage = StorageService();
    final enabled = await storage.getTelemetryEnabled();
    if (!enabled) return;

    final payload = await _buildBasePayload();
    payload['event'] = 'app_launch';
    _send(payload);
  }

  Future<void> reportTelemetryToggle(bool enabled) async {
    final payload = await _buildBasePayload();
    payload['event'] = 'telemetry_toggle';
    payload['telemetry_enabled'] = enabled;
    _send(payload);
  }
}
