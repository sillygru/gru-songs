import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IosFolderSelection {
  final String path;
  final String bookmarkId;

  const IosFolderSelection({
    required this.path,
    required this.bookmarkId,
  });

  factory IosFolderSelection.fromMap(Map<dynamic, dynamic> map) {
    return IosFolderSelection(
      path: map['path'] as String? ?? '',
      bookmarkId: map['bookmarkId'] as String? ??
          map['iosBookmarkId'] as String? ??
          '',
    );
  }
}

class IosFolderAccessService {
  static const MethodChannel _channel =
      MethodChannel('gru_songs/ios_folder_access');

  static Future<IosFolderSelection?> pickFolder() async {
    if (!Platform.isIOS) return null;
    try {
      final result = await _channel.invokeMethod<dynamic>('pickFolder');
      if (result == null) return null;
      return IosFolderSelection.fromMap(
          Map<dynamic, dynamic>.from(result as Map));
    } catch (e) {
      debugPrint('Error picking iOS folder: $e');
      return null;
    }
  }

  static Future<List<Map<String, String>>> loadResolvedFolders() async {
    if (!Platform.isIOS) return [];
    try {
      final result =
          await _channel.invokeMethod<dynamic>('loadResolvedFolders');
      if (result == null) return [];
      final folders = <Map<String, String>>[];
      for (final item in List<dynamic>.from(result as List)) {
        final map = Map<dynamic, dynamic>.from(item as Map);
        folders.add({
          'path': map['path'] as String? ?? '',
          'treeUri': map['treeUri'] as String? ?? '',
          'platform': map['platform'] as String? ?? 'ios',
          'iosBookmarkId': map['iosBookmarkId'] as String? ?? '',
        });
      }
      return folders;
    } catch (e) {
      debugPrint('Error resolving iOS folders: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> loadPersistedFolders() async {
    if (!Platform.isIOS) return [];
    try {
      final result =
          await _channel.invokeMethod<dynamic>('loadPersistedFolders');
      if (result == null) return [];
      final folders = <Map<String, String>>[];
      for (final item in List<dynamic>.from(result as List)) {
        final map = Map<dynamic, dynamic>.from(item as Map);
        folders.add({
          'path': map['path'] as String? ?? '',
          'treeUri': map['treeUri'] as String? ?? '',
          'platform': map['platform'] as String? ?? 'ios',
          'iosBookmarkId': map['iosBookmarkId'] as String? ?? '',
        });
      }
      return folders;
    } catch (e) {
      debugPrint('Error loading persisted iOS folders: $e');
      return [];
    }
  }

  static Future<void> removeFolder(String bookmarkId) async {
    if (!Platform.isIOS || bookmarkId.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('removeFolder', {
        'bookmarkId': bookmarkId,
      });
    } catch (e) {
      debugPrint('Error removing iOS folder bookmark: $e');
    }
  }
}
