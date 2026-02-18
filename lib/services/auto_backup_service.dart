import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'backup_service.dart';
import 'storage_service.dart';

class AutoBackupResult {
  final bool success;
  final String? backupFilename;
  final String? errorMessage;
  final bool permissionDenied;

  AutoBackupResult({
    required this.success,
    this.backupFilename,
    this.errorMessage,
    this.permissionDenied = false,
  });
}

class AutoBackupService {
  static const String _lastAutoBackupKey = 'last_auto_backup_timestamp';
  static final AutoBackupService _instance = AutoBackupService._internal();
  factory AutoBackupService() => _instance;
  AutoBackupService._internal();

  static AutoBackupService get instance => _instance;

  Future<bool> shouldRunAutoBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final frequencyHours = prefs.getInt('auto_backup_frequency_hours') ?? 0;

      if (frequencyHours == 0) {
        return false;
      }

      final lastBackupMs = prefs.getInt(_lastAutoBackupKey);
      if (lastBackupMs == null || lastBackupMs == 0) {
        return true;
      }

      final lastBackup = DateTime.fromMillisecondsSinceEpoch(lastBackupMs);
      
      if (!await _lastAutoBackupStillExists(lastBackup)) {
        return true;
      }
      
      final now = DateTime.now();
      final hoursSince = now.difference(lastBackup).inHours;

      if (hoursSince >= frequencyHours) {
        return true;
      }

      if (isCloseToThreshold(hoursSince, frequencyHours)) {
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error checking auto-backup status: $e');
      return false;
    }
  }

  Future<bool> _lastAutoBackupStillExists(DateTime lastBackup) async {
    try {
      final backups = await BackupService.instance.getBackupsList();
      if (backups.isEmpty) {
        return false;
      }
      
      final newestBackup = backups.first;
      final timeDiff = newestBackup.timestamp.difference(lastBackup).abs();
      
      if (timeDiff.inMinutes < 1) {
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error checking if last auto-backup still exists: $e');
      return false;
    }
  }

  bool isCloseToThreshold(int hoursSince, int frequency) {
    final hoursUntilThreshold = frequency - hoursSince;
    return hoursUntilThreshold <= 2;
  }

  Future<AutoBackupResult> performAutoBackup() async {
    try {
      final hasPermission = await _checkStoragePermission();
      if (!hasPermission) {
        return AutoBackupResult(
          success: false,
          errorMessage: 'Storage permission required',
          permissionDenied: true,
        );
      }

      final backupFilename = await BackupService.instance.createBackup();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastAutoBackupKey, DateTime.now().millisecondsSinceEpoch);

      await _autoDeleteOldBackups();

      return AutoBackupResult(
        success: true,
        backupFilename: backupFilename,
      );
    } on PermissionDeniedException catch (e) {
      return AutoBackupResult(
        success: false,
        errorMessage: 'Storage permission denied: $e',
        permissionDenied: true,
      );
    } catch (e) {
      debugPrint('Auto-backup failed: $e');
      return AutoBackupResult(
        success: false,
        errorMessage: 'Auto-backup failed: $e',
      );
    }
  }

  Future<bool> _checkStoragePermission() async {
    try {
      final status = await Permission.manageExternalStorage.status;
      if (status.isGranted) {
        return true;
      }

      if (status.isDenied) {
        final requested = await Permission.manageExternalStorage.request();
        return requested.isGranted;
      }

      if (status.isPermanentlyDenied) {
        return false;
      }

      return false;
    } catch (e) {
      debugPrint('Error checking storage permission: $e');
      return false;
    }
  }

  Future<void> requestStoragePermission() async {
    try {
      await Permission.manageExternalStorage.request();
    } catch (e) {
      debugPrint('Error requesting storage permission: $e');
    }
  }

  Future<void> _autoDeleteOldBackups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deleteAfterDays = prefs.getInt('auto_backup_delete_after_days') ?? 0;

      if (deleteAfterDays == 0) {
        return;
      }

      final backups = await BackupService.instance.getBackupsList();
      if (backups.length <= 1) {
        return;
      }

      final cutoffDate = DateTime.now().subtract(Duration(days: deleteAfterDays));

      for (final backup in backups) {
        if (backup.timestamp.isBefore(cutoffDate)) {
          if (backups.length > 1) {
            await BackupService.instance.deleteBackup(backup);
            debugPrint('Auto-deleted old backup: ${backup.filename}');
          }
        }
      }
    } catch (e) {
      debugPrint('Error during auto-delete of old backups: $e');
    }
  }

  Future<DateTime?> getLastAutoBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastBackupMs = prefs.getInt(_lastAutoBackupKey);
      if (lastBackupMs == null || lastBackupMs == 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(lastBackupMs);
    } catch (e) {
      debugPrint('Error getting last auto-backup time: $e');
      return null;
    }
  }

  Future<void> resetLastAutoBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastAutoBackupKey);
    } catch (e) {
      debugPrint('Error resetting last auto-backup: $e');
    }
  }

  Future<String?> getPermissionErrorMessage() async {
    try {
      final status = await Permission.manageExternalStorage.status;
      if (status.isPermanentlyDenied) {
        return 'Wispie needs access to all files to create backups. Please grant permission in system settings.';
      } else if (status.isDenied) {
        return 'Storage permission is required to create backups.';
      }
      return null;
    } catch (e) {
      debugPrint('Error getting permission status: $e');
      return null;
    }
  }

  Future<void> openSystemAppSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      debugPrint('Error opening app settings: $e');
    }
  }
}

class PermissionDeniedException implements Exception {
  final String message;
  PermissionDeniedException(this.message);
  @override
  String toString() => 'PermissionDeniedException: $message';
}
