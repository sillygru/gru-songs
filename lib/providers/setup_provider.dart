import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';

class SetupNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false; // Default, overridden in main
  }

  void setComplete(bool value) {
    state = value;
  }
  
  Future<void> checkStatus() async {
    final storage = StorageService();
    state = await storage.getIsSetupComplete();
  }
}

final setupProvider = NotifierProvider<SetupNotifier, bool>(() {
  return SetupNotifier();
});
