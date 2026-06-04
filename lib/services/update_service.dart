import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateReleaseInfo {
  final String tagName;
  final Uri releaseUrl;

  const UpdateReleaseInfo({
    required this.tagName,
    required this.releaseUrl,
  });
}

class UpdateService {
  static const String _latestReleaseApi =
      'https://api.github.com/repos/sillygru/wispie/releases/latest';
  static const String latestReleaseUrl =
      'https://github.com/sillygru/wispie/releases/latest';
  static const String _dismissedVersionKey = 'update_dismissed_version';

  static Future<bool> isVersionDismissed(String tagName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dismissedVersionKey) == tagName;
  }

  static Future<void> dismissVersion(String tagName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedVersionKey, tagName);
  }

  Future<UpdateReleaseInfo?> fetchLatestRelease() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_latestReleaseApi));
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Wispie');

      final response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) return null;

      final responseBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) return null;

      final tagName = decoded['tag_name']?.toString().trim();
      if (tagName == null || tagName.isEmpty) return null;

      final releaseUrl = Uri.tryParse(decoded['html_url']?.toString() ?? '') ??
          Uri.parse(latestReleaseUrl);
      return UpdateReleaseInfo(
        tagName: tagName,
        releaseUrl: releaseUrl,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> openLatestRelease({Uri? url}) async {
    final target = url ?? Uri.parse(latestReleaseUrl);
    return launchUrl(
      target,
      mode: LaunchMode.externalApplication,
    );
  }

  static bool isNewerVersion(String latest, String current) {
    return compareVersions(latest, current) > 0;
  }

  static int compareVersions(String latest, String current) {
    final latestParts = _parseVersion(latest);
    final currentParts = _parseVersion(current);
    if (latestParts == null || currentParts == null) return 0;

    for (var i = 0; i < 3; i++) {
      final diff = latestParts[i].compareTo(currentParts[i]);
      if (diff != 0) return diff;
    }
    return 0;
  }

  static String normalizedVersionLabel(String value) {
    final parsed = _normalizeVersionString(value);
    return parsed ?? value;
  }

  static List<int>? _parseVersion(String value) {
    final normalized = _normalizeVersionString(value);
    if (normalized == null) return null;

    final parts = normalized.split('.');
    if (parts.isEmpty) return null;

    final numbers = <int>[];
    for (var i = 0; i < 3; i++) {
      if (i >= parts.length) {
        numbers.add(0);
        continue;
      }
      final parsed = int.tryParse(parts[i]);
      if (parsed == null) return null;
      numbers.add(parsed);
    }
    return numbers;
  }

  static String? _normalizeVersionString(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final withoutPrefix = trimmed.replaceFirst(RegExp(r'^[vV]'), '');
    final core = withoutPrefix.split(RegExp(r'[-+]')).first.trim();
    return core.isEmpty ? null : core;
  }
}
