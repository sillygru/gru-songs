import 'dart:convert';
import 'dart:io';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'cache_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

class WaveformService {
  final CacheService _cacheService;
  final PlayerController _extractionController = PlayerController();

  WaveformService(this._cacheService);

  Future<List<double>> getWaveform(String filename, String path) async {
    // Only support local files
    if (path.isEmpty || path.startsWith('http')) return [];

    final cacheFile = await _cacheService.getV3File('waveform_$filename.json');
    if (await cacheFile.exists()) {
      try {
        final content = await cacheFile.readAsString();
        final List<dynamic> json = jsonDecode(content);
        return json.cast<double>();
      } catch (e) {
        debugPrint('Error reading waveform cache: $e');
      }
    }

    // Extract if not cached
    RandomAccessFile? lockHandle;
    try {
      lockHandle = await _acquireSharedLock(path);
      final file = File(path);
      if (!await file.exists()) return [];

      final samples = await _extractionController.extractWaveformData(
        path: path,
        noOfSamples: 2000,
      );

      if (samples.isEmpty) return [];

      final clampedSamples = samples.map((v) => v.clamp(0.0, 1.0)).toList();

      // Cache it
      await cacheFile.writeAsString(jsonEncode(clampedSamples));
      return clampedSamples;
    } catch (e) {
      debugPrint('Error extracting waveform for $filename: $e');
      return [];
    } finally {
      await _releaseLock(lockHandle);
    }
  }

  Future<RandomAccessFile?> _acquireSharedLock(String filePath) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final lockDir = Directory(p.join(supportDir.path, 'file_locks'));
      if (!await lockDir.exists()) {
        await lockDir.create(recursive: true);
      }
      final hash = md5.convert(utf8.encode(filePath)).toString();
      final lockFile = File(p.join(lockDir.path, '$hash.lock'));
      final raf = await lockFile.open(mode: FileMode.append);
      await raf.lock(FileLock.shared);
      return raf;
    } catch (e) {
      debugPrint('Waveform: failed to acquire lock for $filePath: $e');
      return null;
    }
  }

  Future<void> _releaseLock(RandomAccessFile? raf) async {
    if (raf == null) return;
    try {
      await raf.unlock();
    } catch (_) {
      // Best-effort unlock
    }
    try {
      await raf.close();
    } catch (_) {
      // Ignore close errors
    }
  }

  void dispose() {
    _extractionController.dispose();
  }
}
