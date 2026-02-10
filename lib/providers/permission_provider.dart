import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final storagePermissionProvider = FutureProvider<bool>((ref) async {
  if (Platform.isAndroid) {
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }
  return true;
});

final requestStoragePermissionProvider =
    Provider<Future<bool> Function()>((ref) {
  return () async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      // Refresh the provider
      ref.invalidate(storagePermissionProvider);
      return status.isGranted;
    }
    return true;
  };
});
