import 'dart:collection';
import 'package:wakelock_plus/wakelock_plus.dart';

class ScreenWakeLockService {
  ScreenWakeLockService._();
  static final ScreenWakeLockService instance = ScreenWakeLockService._();

  final Set<String> _reasons = HashSet<String>();

  Future<void> acquire(String reason) async {
    _reasons.add(reason);
    if (_reasons.length == 1) {
      await WakelockPlus.enable();
    }
  }

  Future<void> release(String reason) async {
    _reasons.remove(reason);
    if (_reasons.isEmpty) {
      await WakelockPlus.disable();
    }
  }
}
