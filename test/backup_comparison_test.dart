import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/services/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Backup Comparison Tests', () {
    late Directory tempDir;
    late BackupService backupService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('backup_test_');
      backupService = BackupService.instance;
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<File> createMockBackup({
      required String filename,
      required int songCount,
      required int statsRows,
      required int sizeBytes,
    }) async {
      final backupDir = await Directory(
              p.join(tempDir.path, 'mock_backup_${filename.hashCode}'))
          .create();

      // Create songs.json
      final songs =
          List.generate(songCount, (i) => {'id': i, 'title': 'Song $i'});
      await File(p.join(backupDir.path, 'songs.json'))
          .writeAsString(jsonEncode(songs));

      // Create stats db
      final dbPath = p.join(backupDir.path, 'test_user_stats.db');
      final db = await openDatabase(dbPath);
      await db.execute(
          'CREATE TABLE playevent (id INTEGER PRIMARY KEY, song_filename TEXT)');
      for (var i = 0; i < statsRows; i++) {
        await db.insert('playevent', {'song_filename': 'song_$i.mp3'});
      }
      await db.close();

      // Zip it
      final zipFile = File(p.join(tempDir.path, filename));
      final archive = Archive();

      final songsFile = File(p.join(backupDir.path, 'songs.json'));
      final songsBytes = await songsFile.readAsBytes();
      archive.addFile(ArchiveFile('songs.json', songsBytes.length, songsBytes));

      final statsFile = File(dbPath);
      final statsBytes = await statsFile.readAsBytes();
      archive.addFile(
          ArchiveFile('test_user_stats.db', statsBytes.length, statsBytes));

      final zipBytes = ZipEncoder().encode(archive);
      await zipFile.writeAsBytes(zipBytes!);

      await backupDir.delete(recursive: true);

      return zipFile;
    }

    test('compareBackups calculates differences correctly', () async {
      final oldFile = await createMockBackup(
        filename: 'old.zip',
        songCount: 10,
        statsRows: 5,
        sizeBytes: 1000,
      );

      final newFile = await createMockBackup(
        filename: 'new.zip',
        songCount: 15,
        statsRows: 8,
        sizeBytes: 2000,
      );

      final oldBackup = BackupInfo(
        number: 1,
        timestamp: DateTime.now(),
        filename: 'old.zip',
        file: oldFile,
        sizeBytes: 1000,
      );

      final newBackup = BackupInfo(
        number: 2,
        timestamp: DateTime.now(),
        filename: 'new.zip',
        file: newFile,
        sizeBytes: 2000,
      );

      final diff = await backupService.compareBackups(oldBackup, newBackup);

      expect(diff.songCountDiff, equals(5));
      expect(diff.statsRowsDiff, equals(3));
      // Zip size will vary due to compression/headers, so we check if diff is positive/consistent with inputs if we mocked sizes manually in BackupInfo
      // In BackupInfo constructor we passed 1000 and 2000, so diff should be 1000.
      expect(diff.sizeBytesDiff, equals(1000));
    });

    test('compareBackups handles missing files gracefully', () async {
      // Create backup without stats db
      final emptyBackupDir =
          await Directory(p.join(tempDir.path, 'empty_backup')).create();
      await File(p.join(emptyBackupDir.path, 'songs.json')).writeAsString('[]');

      final zipFile = File(p.join(tempDir.path, 'empty.zip'));
      final archive = Archive();
      final songsBytes =
          await File(p.join(emptyBackupDir.path, 'songs.json')).readAsBytes();
      archive.addFile(ArchiveFile('songs.json', songsBytes.length, songsBytes));

      await zipFile.writeAsBytes(ZipEncoder().encode(archive)!);
      await emptyBackupDir.delete(recursive: true);

      final backupInfo = BackupInfo(
          number: 1,
          timestamp: DateTime.now(),
          filename: 'empty.zip',
          file: zipFile,
          sizeBytes: 100);

      final diff = await backupService.compareBackups(backupInfo, backupInfo);

      expect(diff.songCountDiff, 0);
      expect(diff.statsRowsDiff, 0);
      expect(diff.sizeBytesDiff, 0);
    });
  });
}
