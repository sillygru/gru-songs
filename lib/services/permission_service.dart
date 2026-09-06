import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'android_storage_service.dart';

final permissionServiceProvider =
    Provider<PermissionService>((ref) => PermissionService.instance);

class PermissionService {
  static final PermissionService instance = PermissionService._internal();

  PermissionService._internal();

  factory PermissionService() => instance;

  /// Checks whether storage permission is currently granted.
  ///
  /// On Android 10 and lower (SDK < 30), MANAGE_EXTERNAL_STORAGE does not exist,
  /// so standard storage permission (READ/WRITE_EXTERNAL_STORAGE) is checked.
  /// On Android 11 and higher (SDK >= 30), MANAGE_EXTERNAL_STORAGE is checked first,
  /// with a fallback to media/storage permissions.
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    if (Platform.isIOS) {
      final status = await Permission.photos.status;
      return status.isGranted || status.isLimited;
    }

    final sdk = await AndroidStorageService.getSdkInt();
    if (sdk > 0 && sdk < 30) {
      return await Permission.storage.isGranted;
    }

    final statusManage = await Permission.manageExternalStorage.status;
    if (statusManage.isGranted) {
      return true;
    }

    final statusStorage = await Permission.storage.status;
    final statusAudio = await Permission.audio.status;
    return statusStorage.isGranted || statusAudio.isGranted;
  }

  /// Requests storage permission suitable for the current Android version.
  ///
  /// On Android 10 and lower (SDK < 30), requests standard storage permission.
  /// On Android 11 and higher (SDK >= 30), requests MANAGE_EXTERNAL_STORAGE.
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }

    final sdk = await AndroidStorageService.getSdkInt();
    if (sdk > 0 && sdk < 30) {
      final status = await Permission.storage.request();
      return status.isGranted;
    }

    final statusManage = await Permission.manageExternalStorage.request();
    if (statusManage.isGranted) {
      return true;
    }

    final statusAudio = await Permission.audio.request();
    if (statusAudio.isGranted) {
      return true;
    }

    final statusStorage = await Permission.storage.request();
    return statusStorage.isGranted;
  }

  /// Checks if storage permission has been permanently denied.
  Future<bool> isStoragePermissionPermanentlyDenied() async {
    if (!Platform.isAndroid) {
      return false;
    }

    final sdk = await AndroidStorageService.getSdkInt();
    if (sdk > 0 && sdk < 30) {
      return await Permission.storage.isPermanentlyDenied;
    }

    return await Permission.manageExternalStorage.isPermanentlyDenied;
  }
}
