import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/services/backup_service.dart';
import 'dart:io';

void main() {
  group('BackupService Tests', () {
    late BackupService backupService;

    setUp(() {
      backupService = BackupService.instance;
    });

    test('BackupService can be instantiated', () {
      expect(backupService, isNotNull);
      expect(BackupService.instance, equals(backupService)); // Singleton test
    });

    test('BackupInfo display formatting', () {
      final backupInfo = BackupInfo(
        number: 5,
        timestamp: DateTime(2026, 1, 27, 17, 58),
        filename: '005_2026_01_27_17-58.zip',
        file: File('test'),
        sizeBytes: 1024 * 1024, // 1MB
      );

      expect(backupInfo.displayName, equals('Backup #5 - 2026_01_27_17-58'));
      expect(backupInfo.formattedSize, equals('1.0MB'));

      // Test size formatting for different sizes
      final smallBackup = BackupInfo(
        number: 1,
        timestamp: DateTime.now(),
        filename: '001_2026_01_27_17-58.zip',
        file: File('test'),
        sizeBytes: 512,
      );
      expect(smallBackup.formattedSize, equals('512B'));

      final kbBackup = BackupInfo(
        number: 2,
        timestamp: DateTime.now(),
        filename: '002_2026_01_27_17-58.zip',
        file: File('test'),
        sizeBytes: 1024 * 2,
      );
      expect(kbBackup.formattedSize, equals('2.0KB'));
    });

    test('JSON encoding/decoding works', () {
      final testData = {
        'test': 'data',
        'number': 42,
        'list': [1, 2, 3],
      };

      final encoded = backupService.encodeJson(testData);
      expect(encoded, isA<String>());

      final decoded = backupService.decodeJson(encoded);
      expect(decoded, equals(testData));
    });

    test('Can get backups list', () async {
      final backups = await backupService.getBackupsList();
      expect(backups, isA<List<BackupInfo>>());
    });
  });

  group('Backup Integration Tests', () {
    test('Full backup and restore workflow', () async {
      // This would be a more comprehensive integration test
      // that would require setting up a test database and files
      // For now, we'll just verify the service exists and can be called

      final backupService = BackupService.instance;
      expect(backupService, isNotNull);
      expect(backupService.getBackupsList(), completes);
    });
  });
}
