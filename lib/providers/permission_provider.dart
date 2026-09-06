import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/permission_service.dart';

final storagePermissionProvider = FutureProvider<bool>((ref) async {
  return await ref.watch(permissionServiceProvider).hasStoragePermission();
});
