import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';

class DataExportService {
  static const String _metadataFile = 'metadata.json';

  Future<void> exportUserData(String username) async {
    final docDir = await getApplicationDocumentsDirectory();
    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory(join(tempDir.path,
        'export_${username}_${DateTime.now().millisecondsSinceEpoch}'));
    await exportDir.create(recursive: true);

    try {
      // 1. Prepare files
      final statsDbName = '${username}_stats.db';
      final dataDbName = '${username}_data.db';

      final statsDbPath = join(docDir.path, statsDbName);
      final dataDbPath = join(docDir.path, dataDbName);

      if (!await File(statsDbPath).exists() ||
          !await File(dataDbPath).exists()) {
        throw Exception('User databases not found');
      }

      // Copy to temp export dir
      await File(statsDbPath).copy(join(exportDir.path, statsDbName));
      await File(dataDbPath).copy(join(exportDir.path, dataDbName));

      // 2. Create metadata
      final metadata = {
        'username': username,
        'export_date': DateTime.now().toIso8601String(),
        'version': '1.0',
      };
      await File(join(exportDir.path, _metadataFile))
          .writeAsString(jsonEncode(metadata));

      // 3. Zip it up
      final encoder = ZipFileEncoder();
      final zipPath = join(tempDir.path, 'gru_songs_backup_$username.zip');
      encoder.create(zipPath);
      encoder.addDirectory(exportDir);
      encoder.close();

      // 4. Share
      final xFile = XFile(zipPath);
      await Share.shareXFiles([xFile], text: 'Gru Songs Backup for $username');
    } finally {
      // Cleanup
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true);
      }
    }
  }

  Future<Map<String, dynamic>?> validateBackup(String currentUsername) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || result.files.isEmpty) return null;

    final file = File(result.files.first.path!);
    final tempDir = await getTemporaryDirectory();
    final decodeDir = Directory(
        join(tempDir.path, 'import_${DateTime.now().millisecondsSinceEpoch}'));
    await decodeDir.create(recursive: true);

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          File(join(decodeDir.path, filename))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        }
      }

      // Check for nested directory (ZipFileEncoder.addDirectory adds the directory itself)
      // We need to find where metadata.json is.
      File? metadataFile;
      String contentPath = decodeDir.path;

      final entities = decodeDir.listSync();
      if (entities.length == 1 && entities.first is Directory) {
        contentPath = entities.first.path;
      }

      metadataFile = File(join(contentPath, _metadataFile));

      if (!await metadataFile.exists()) {
        throw Exception('Invalid backup: metadata.json missing');
      }

      final metadata = jsonDecode(await metadataFile.readAsString());
      if (metadata['username'] != currentUsername) {
        return {
          'valid': false,
          'error':
              'Account mismatch. Backup is for "${metadata['username']}", but you are "$currentUsername".',
          'importPath': contentPath,
        };
      }

      // Check for DB files
      final statsDbName = '${currentUsername}_stats.db';
      final dataDbName = '${currentUsername}_data.db';
      if (!await File(join(contentPath, statsDbName)).exists() ||
          !await File(join(contentPath, dataDbName)).exists()) {
        throw Exception('Invalid backup: Database files missing');
      }

      return {
        'valid': true,
        'metadata': metadata,
        'importPath': contentPath,
      };
    } catch (e) {
      if (await decodeDir.exists()) await decodeDir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> performImport({
    required String username,
    required String importPath,
    required bool additive,
  }) async {
    final statsDbName = '${username}_stats.db';
    final dataDbName = '${username}_data.db';

    final importedStatsDbPath = join(importPath, statsDbName);
    final importedDataDbPath = join(importPath, dataDbName);

    await DatabaseService.instance.importData(
      statsDbPath: importedStatsDbPath,
      dataDbPath: importedDataDbPath,
      additive: additive,
    );

    // Cleanup import path
    final importDir = Directory(importPath);
    // Note: importPath might be a subdirectory of the actual temp import dir
    // but we can just delete the parent if it matches our pattern.
    if (importDir.parent.path.contains('import_')) {
      await importDir.parent.delete(recursive: true);
    } else {
      await importDir.delete(recursive: true);
    }
  }
}
