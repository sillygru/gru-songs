import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auto_backup_service.dart';

class AutoBackupState {
  final int frequencyHours;
  final int deleteAfterDays;
  final DateTime? lastAutoBackup;
  final bool isRunning;
  final AutoBackupResult? lastResult;
  final bool hasPermissionError;

  AutoBackupState({
    this.frequencyHours = 0,
    this.deleteAfterDays = 0,
    this.lastAutoBackup,
    this.isRunning = false,
    this.lastResult,
    this.hasPermissionError = false,
  });

  AutoBackupState copyWith({
    int? frequencyHours,
    int? deleteAfterDays,
    DateTime? lastAutoBackup,
    bool? isRunning,
    AutoBackupResult? lastResult,
    bool? hasPermissionError,
  }) {
    return AutoBackupState(
      frequencyHours: frequencyHours ?? this.frequencyHours,
      deleteAfterDays: deleteAfterDays ?? this.deleteAfterDays,
      lastAutoBackup: lastAutoBackup ?? this.lastAutoBackup,
      isRunning: isRunning ?? this.isRunning,
      lastResult: lastResult ?? this.lastResult,
      hasPermissionError: hasPermissionError ?? this.hasPermissionError,
    );
  }

  bool get isEnabled => frequencyHours > 0;
}

class AutoBackupNotifier extends Notifier<AutoBackupState> {
  @override
  AutoBackupState build() {
    _loadState();
    return AutoBackupState();
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final frequencyHours = prefs.getInt('auto_backup_frequency_hours') ?? 0;
      final deleteAfterDays =
          prefs.getInt('auto_backup_delete_after_days') ?? 0;
      final lastBackupMs = prefs.getInt('last_auto_backup_timestamp');

      DateTime? lastAutoBackup;
      if (lastBackupMs != null && lastBackupMs > 0) {
        lastAutoBackup = DateTime.fromMillisecondsSinceEpoch(lastBackupMs);
      }

      state = state.copyWith(
        frequencyHours: frequencyHours,
        deleteAfterDays: deleteAfterDays,
        lastAutoBackup: lastAutoBackup,
      );
    } catch (e) {
      debugPrint('Error loading auto-backup state: $e');
    }
  }

  Future<void> setFrequencyHours(int hours) async {
    try {
      state = state.copyWith(frequencyHours: hours);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('auto_backup_frequency_hours', hours);

      if (hours == 0) {
        await AutoBackupService.instance.resetLastAutoBackup();
        state = state.copyWith(lastAutoBackup: null);
      }
    } catch (e) {
      debugPrint('Error setting auto-backup frequency: $e');
    }
  }

  Future<void> setDeleteAfterDays(int days) async {
    try {
      state = state.copyWith(deleteAfterDays: days);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('auto_backup_delete_after_days', days);
    } catch (e) {
      debugPrint('Error setting auto-backup delete-after-days: $e');
    }
  }

  Future<void> checkAndRunAutoBackup() async {
    if (!state.isEnabled || state.isRunning) {
      return;
    }

    final shouldRun = await AutoBackupService.instance.shouldRunAutoBackup();
    if (!shouldRun) {
      return;
    }

    state = state.copyWith(isRunning: true, hasPermissionError: false);

    try {
      final result = await AutoBackupService.instance.performAutoBackup();

      state = state.copyWith(
        isRunning: false,
        lastResult: result,
        hasPermissionError: result.permissionDenied,
      );

      if (result.success) {
        await _loadState();
      }
    } catch (e) {
      debugPrint('Auto-backup check failed: $e');
      state = state.copyWith(
        isRunning: false,
        lastResult: AutoBackupResult(
          success: false,
          errorMessage: 'Auto-backup check failed: $e',
        ),
      );
    }
  }

  Future<void> clearLastError() async {
    state = state.copyWith(lastResult: null, hasPermissionError: false);
  }

  Future<void> requestPermission() async {
    try {
      await AutoBackupService.instance.requestStoragePermission();
      await checkAndRunAutoBackup();
    } catch (e) {
      debugPrint('Error requesting permission: $e');
    }
  }

  Future<void> openSystemSettings() async {
    try {
      await AutoBackupService.instance.openSystemAppSettings();
    } catch (e) {
      debugPrint('Error opening system settings: $e');
    }
  }
}

final autoBackupProvider =
    NotifierProvider<AutoBackupNotifier, AutoBackupState>(
  AutoBackupNotifier.new,
);
