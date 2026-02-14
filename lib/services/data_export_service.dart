import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';

class DataExportService {
  static const String _metadataFile = 'metadata.json';

  Future<void> exportUserData() async {
    final docDir = await getApplicationDocumentsDirectory();
    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory(p.join(
        tempDir.path, 'export_${DateTime.now().millisecondsSinceEpoch}'));
    await exportDir.create(recursive: true);

    try {
      // 1. Prepare files
      final statsDbName = 'wispie_stats.db';
      final dataDbName = 'wispie_data.db';

      final statsDbPath = p.join(docDir.path, statsDbName);
      final dataDbPath = p.join(docDir.path, dataDbName);

      if (!await File(statsDbPath).exists() ||
          !await File(dataDbPath).exists()) {
        throw Exception('User databases not found');
      }

      // Copy to temp export dir
      await File(statsDbPath).copy(p.join(exportDir.path, statsDbName));
      await File(dataDbPath).copy(p.join(exportDir.path, dataDbName));

      // 2. Create metadata
      final metadata = {
        'export_date': DateTime.now().toIso8601String(),
        'version': '1.0',
      };
      await File(p.join(exportDir.path, _metadataFile))
          .writeAsString(jsonEncode(metadata));

      // 3. Zip it up
      final encoder = ZipFileEncoder();
      final zipPath = p.join(tempDir.path, 'wispie_backup.zip');
      encoder.create(zipPath);
      encoder.addDirectory(exportDir);
      encoder.close();

      // 4. Share
      final bytes = await File(zipPath).readAsBytes();
      final xFile = XFile.fromData(
        bytes,
        name: p.basename(zipPath),
        mimeType: 'application/zip',
      );
      await Share.shareXFiles([xFile], text: 'Wispie Backup');
    } finally {
      // Cleanup
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true);
      }
    }
  }

  Future<Map<String, dynamic>?> validateBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || result.files.isEmpty) return null;

    final file = File(result.files.first.path!);
    final tempDir = await getTemporaryDirectory();
    final decodeDir = Directory(p.join(
        tempDir.path, 'import_${DateTime.now().millisecondsSinceEpoch}'));
    await decodeDir.create(recursive: true);

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          File(p.join(decodeDir.path, filename))
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

      metadataFile = File(p.join(contentPath, _metadataFile));

      if (!await metadataFile.exists()) {
        throw Exception('Invalid backup: metadata.json missing');
      }

      final metadata = jsonDecode(await metadataFile.readAsString());

      // Check for DB files
      // Try both wispie_ and legacy prefixes
      File? foundStats;
      File? foundData;

      final statsDbName = 'wispie_stats.db';
      final dataDbName = 'wispie_data.db';

      await for (final entity in Directory(contentPath).list(recursive: true)) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name == statsDbName ||
              (name.endsWith('_stats.db') && !name.startsWith('wispie_'))) {
            foundStats = entity;
          }
          if (name == dataDbName ||
              (name.endsWith('_data.db') && !name.startsWith('wispie_'))) {
            foundData = entity;
          }
        }
      }

      if (foundStats == null || foundData == null) {
        throw Exception('Invalid backup: Database files missing');
      }

      return {
        'valid': true,
        'metadata': metadata,
        'importPath': contentPath,
        'statsDbPath': foundStats.path,
        'dataDbPath': foundData.path,
      };
    } catch (e) {
      if (await decodeDir.exists()) await decodeDir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> performImport({
    required String statsDbPath,
    required String dataDbPath,
    required bool additive,
  }) async {
    await DatabaseService.instance.importData(
      statsDbPath: statsDbPath,
      dataDbPath: dataDbPath,
      additive: additive,
    );

    // Cleanup import dir - logic to find the temp root
    final importDir = Directory(p.dirname(statsDbPath));
    // Find the one containing "import_"
    Directory? toDelete = importDir;
    while (toDelete != null && !p.basename(toDelete.path).contains('import_')) {
      if (toDelete.path == toDelete.parent.path) break;
      toDelete = toDelete.parent;
    }

    if (toDelete != null && p.basename(toDelete.path).contains('import_')) {
      await toDelete.delete(recursive: true);
    }
  }
}
