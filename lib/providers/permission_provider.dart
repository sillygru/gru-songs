import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final storagePermissionProvider = FutureProvider<bool>((ref) async {
  if (Platform.isAndroid) {
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  } else if (Platform.isIOS) {
    final status = await Permission.photos.status;
    return status.isGranted || status.isLimited;
  }
  return true;
});
