import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class AndroidTreeSelection {
  final String treeUri;
  final String? path;

  const AndroidTreeSelection({required this.treeUri, this.path});
}

class AndroidStorageService {
  static const MethodChannel _channel = MethodChannel('wispie/storage');
  static int? _cachedSdkInt;

  /// Returns the Android SDK version (Build.VERSION.SDK_INT), or 0 on non-Android platforms.
  static Future<int> getSdkInt() async {
    if (_cachedSdkInt != null) return _cachedSdkInt!;
    if (!Platform.isAndroid) return 0;
    try {
      final sdk = await _channel.invokeMethod<int>('getSdkInt');
      _cachedSdkInt = sdk ?? 0;
      return _cachedSdkInt!;
    } catch (e) {
      debugPrint('Failed to get Android SDK version: $e');
      return 0;
    }
  }

  @visibleForTesting
  static void setMockSdkInt(int? sdk) {
    _cachedSdkInt = sdk;
  }

  static Future<AndroidTreeSelection?> pickTree() async {
    if (!Platform.isAndroid) return null;
    final result = await _channel.invokeMethod<dynamic>('pickTree');
    if (result == null) return null;

    final map = Map<String, dynamic>.from(result as Map);
    final treeUri = map['treeUri'] as String?;
    if (treeUri == null || treeUri.isEmpty) return null;

    return AndroidTreeSelection(
      treeUri: treeUri,
      path: map['path'] as String?,
    );
  }

  static Future<void> createFolder({
    required String treeUri,
    required String relativePath,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('createFolder', {
      'treeUri': treeUri,
      'relativePath': relativePath,
    });
  }

  static Future<void> moveFile({
    required String treeUri,
    required String sourceRelativePath,
    required String targetRelativeDir,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('moveFile', {
      'treeUri': treeUri,
      'sourceRelativePath': sourceRelativePath,
      'targetRelativeDir': targetRelativeDir,
    });
  }

  static Future<void> renameFile({
    required String treeUri,
    required String sourceRelativePath,
    required String newName,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('renameFile', {
      'treeUri': treeUri,
      'sourceRelativePath': sourceRelativePath,
      'newName': newName,
    });
  }

  static Future<void> deleteFile({
    required String treeUri,
    required String sourceRelativePath,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('deleteFile', {
      'treeUri': treeUri,
      'sourceRelativePath': sourceRelativePath,
    });
  }

  static Future<void> writeFileFromPath({
    required String treeUri,
    required String sourceRelativePath,
    required String sourcePath,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('writeFileFromPath', {
      'treeUri': treeUri,
      'sourceRelativePath': sourceRelativePath,
      'sourcePath': sourcePath,
    });
  }

  static Future<void> moveFolder({
    required String treeUri,
    required String sourceRelativePath,
    required String targetParentRelativePath,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('moveFolder', {
      'treeUri': treeUri,
      'sourceRelativePath': sourceRelativePath,
      'targetParentRelativePath': targetParentRelativePath,
    });
  }

  static Future<String?> readFile({
    required String treeUri,
    required String relativePath,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMethod<String>('readFile', {
        'treeUri': treeUri,
        'relativePath': relativePath,
      });
      return result;
    } catch (e) {
      debugPrint('Error reading file via Android storage: $e');
      return null;
    }
  }
}
