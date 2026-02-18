import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import '../models/song.dart';
import '../services/database_service.dart';
import '../services/scanner_service.dart';
import '../services/waveform_service.dart';
import '../services/color_extraction_service.dart';
import '../services/cache_service.dart';
import '../services/database_optimizer_service.dart';
import '../domain/services/search_service.dart';
import '../data/repositories/song_repository.dart';

/// Represents the state of an indexer operation
enum IndexerOperationState {
  idle,
  running,
  completed,
  cancelled,
  error,
}

/// Represents a single indexer operation with its progress
class IndexerOperation {
  final String id;
  final String name;
  final String description;
  final IndexerOperationState state;
  final int processedCount;
  final int totalCount;
  final int targetCount;
  final int failedCount;
  final List<String> failedItems;
  final String? errorMessage;
  final bool isBlocking;
  final bool requiresRestart;

  const IndexerOperation({
    required this.id,
    required this.name,
    required this.description,
    this.state = IndexerOperationState.idle,
    this.processedCount = 0,
    this.totalCount = 0,
    this.targetCount = 0,
    this.failedCount = 0,
    this.failedItems = const [],
    this.errorMessage,
    this.isBlocking = false,
    this.requiresRestart = false,
  });

  IndexerOperation copyWith({
    IndexerOperationState? state,
    int? processedCount,
    int? totalCount,
    int? targetCount,
    int? failedCount,
    List<String>? failedItems,
    String? errorMessage,
  }) {
    return IndexerOperation(
      id: id,
      name: name,
      description: description,
      state: state ?? this.state,
      processedCount: processedCount ?? this.processedCount,
      totalCount: totalCount ?? this.totalCount,
      targetCount: targetCount ?? this.targetCount,
      failedCount: failedCount ?? this.failedCount,
      failedItems: failedItems ?? this.failedItems,
      errorMessage: errorMessage ?? this.errorMessage,
      isBlocking: isBlocking,
      requiresRestart: requiresRestart,
    );
  }

  double get progress => targetCount > 0 ? processedCount / targetCount : 0.0;
  bool get isRunning => state == IndexerOperationState.running;
  String get progressText => '$processedCount/$targetCount';
  bool get isFullyCached =>
      processedCount > 0 && processedCount == totalCount && totalCount > 0;
  bool get isDatabaseOperation =>
      id == 'optimize_stats_db' || id == 'optimize_user_data_db';
}

/// State for all indexer operations
class IndexerState {
  final Map<String, IndexerOperation> operations;
  final bool isInitialized;

  const IndexerState({
    this.operations = const {},
    this.isInitialized = false,
  });

  IndexerState copyWith({
    Map<String, IndexerOperation>? operations,
    bool? isInitialized,
  }) {
    return IndexerState(
      operations: operations ?? this.operations,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }

  IndexerOperation? getOperation(String id) => operations[id];
}

/// Result of an indexer operation
class IndexerResult {
  final bool success;
  final String message;
  final List<String>? warnings;
  final bool requiresRestart;

  const IndexerResult({
    required this.success,
    required this.message,
    this.warnings,
    this.requiresRestart = false,
  });
}

/// Token for canceling operations
class CancelToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  void cancel() => _isCancelled = true;
}

/// Notifier for managing indexer operations
class IndexerNotifier extends Notifier<IndexerState> {
  CancelToken? _currentCancelToken;

  @override
  IndexerState build() {
    return _initializeOperations();
  }

  IndexerState _initializeOperations() {
    final operations = {
      'optimize_stats_db': const IndexerOperation(
        id: 'optimize_stats_db',
        name: 'Optimize Stats Database',
        description: 'Clean and optimize play stats database',
        processedCount: -1,
        isBlocking: true,
        requiresRestart: true,
      ),
      'optimize_user_data_db': const IndexerOperation(
        id: 'optimize_user_data_db',
        name: 'Optimize User Data Database',
        description: 'Clean and optimize user data database',
        processedCount: -1,
        isBlocking: true,
        requiresRestart: true,
      ),
      'rebuild_cover_caches': const IndexerOperation(
        id: 'rebuild_cover_caches',
        name: 'Rebuild Cover Caches',
        description: 'Extract and cache album artwork',
        isBlocking: false,
        requiresRestart: false,
      ),
      'rebuild_search_indexes': const IndexerOperation(
        id: 'rebuild_search_indexes',
        name: 'Rebuild Search Indexes',
        description: 'Rebuild search index for all songs',
        isBlocking: false,
        requiresRestart: false,
      ),
      'rebuild_lyrics_cache': const IndexerOperation(
        id: 'rebuild_lyrics_cache',
        name: 'Rebuild Lyrics Cache',
        description: 'Extract and cache lyrics for all songs',
        isBlocking: false,
        requiresRestart: false,
      ),
      'rebuild_waveform_cache': const IndexerOperation(
        id: 'rebuild_waveform_cache',
        name: 'Rebuild Waveform Cache',
        description: 'Generate waveform data for all songs',
        isBlocking: false,
        requiresRestart: false,
      ),
      'rebuild_color_cache': const IndexerOperation(
        id: 'rebuild_color_cache',
        name: 'Rebuild App Theme on Cover Cache',
        description: 'Extract color themes from all covers',
        isBlocking: false,
        requiresRestart: false,
      ),
    };

    return IndexerState(operations: operations, isInitialized: true);
  }

  /// Load initial counts for all operations
  Future<void> loadCounts() async {
    final songs = await DatabaseService.instance.getAllSongs();
    final totalSongs = songs.length;

    final coverCount = await _getCoverCacheCount();
    final lyricsCount = await _getLyricsCacheCount();
    final waveformCount = await _getWaveformCacheCount();
    final colorCount = await _getColorCacheCount();
    final searchCount = await _getSearchIndexCount();

    final updatedOperations =
        Map<String, IndexerOperation>.from(state.operations);

    // Database operations show "Ready to optimize" with processedCount = -1
    updatedOperations['optimize_stats_db'] =
        updatedOperations['optimize_stats_db']!.copyWith(
      totalCount: totalSongs,
    );

    updatedOperations['optimize_user_data_db'] =
        updatedOperations['optimize_user_data_db']!.copyWith(
      totalCount: totalSongs,
    );

    updatedOperations['rebuild_cover_caches'] =
        updatedOperations['rebuild_cover_caches']!.copyWith(
      processedCount: coverCount,
      totalCount: totalSongs,
      targetCount: totalSongs - coverCount,
    );

    updatedOperations['rebuild_search_indexes'] =
        updatedOperations['rebuild_search_indexes']!.copyWith(
      processedCount: searchCount,
      totalCount: totalSongs,
      targetCount: totalSongs - searchCount,
    );

    updatedOperations['rebuild_lyrics_cache'] =
        updatedOperations['rebuild_lyrics_cache']!.copyWith(
      processedCount: lyricsCount,
      totalCount: totalSongs,
      targetCount: totalSongs - lyricsCount,
    );

    updatedOperations['rebuild_waveform_cache'] =
        updatedOperations['rebuild_waveform_cache']!.copyWith(
      processedCount: waveformCount,
      totalCount: totalSongs,
      targetCount: totalSongs - waveformCount,
    );

    updatedOperations['rebuild_color_cache'] =
        updatedOperations['rebuild_color_cache']!.copyWith(
      processedCount: colorCount,
      totalCount: totalSongs,
      targetCount: totalSongs - colorCount,
    );

    state = state.copyWith(operations: updatedOperations);
  }

  Future<int> _getCoverCacheCount() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory('${supportDir.path}/extracted_covers');
      if (!await coversDir.exists()) return 0;

      int count = 0;
      await for (final entity in coversDir.list()) {
        if (entity is File) count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _getLyricsCacheCount() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final lyricsDir =
          Directory('${supportDir.path}/gru_cache_v3/lyrics_cache');
      if (!await lyricsDir.exists()) return 0;

      int count = 0;
      await for (final entity in lyricsDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _getWaveformCacheCount() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${supportDir.path}/gru_cache_v3');
      if (!await cacheDir.exists()) return 0;

      int count = 0;
      await for (final entity in cacheDir.list()) {
        if (entity is File && entity.path.contains('waveform_')) count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _getColorCacheCount() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final cacheFile = File('${supportDir.path}/palette_cache.json');
      if (!await cacheFile.exists()) return 0;

      final content = await cacheFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return json.length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _getSearchIndexCount() async {
    try {
      final searchService = SearchService();
      await searchService.init();
      final stats = await searchService.getIndexStats();
      await searchService.dispose();
      return stats.totalEntries;
    } catch (_) {
      return 0;
    }
  }

  /// Start an operation
  Future<IndexerResult> startOperation(String operationId,
      {bool force = false}) async {
    final operation = state.operations[operationId];
    if (operation == null) {
      return const IndexerResult(success: false, message: 'Unknown operation');
    }

    if (operation.isRunning) {
      return const IndexerResult(
          success: false, message: 'Operation already running');
    }

    _currentCancelToken = CancelToken();

    // Calculate target count based on force parameter
    int targetCount = operation.totalCount;
    if (!force && !operation.isDatabaseOperation) {
      targetCount = operation.totalCount - operation.processedCount;
      if (targetCount < 0) targetCount = 0;
    }

    // Update operation with target count
    final operations = Map<String, IndexerOperation>.from(state.operations);
    operations[operationId] = operation.copyWith(
      targetCount: targetCount,
      failedCount: 0,
      failedItems: [],
    );
    state = state.copyWith(operations: operations);

    _updateOperationState(operationId, IndexerOperationState.running);

    try {
      final result = await _executeOperation(operationId, force: force);

      if (_currentCancelToken?.isCancelled ?? false) {
        _updateOperationState(operationId, IndexerOperationState.cancelled);
        return const IndexerResult(
            success: false, message: 'Operation cancelled');
      }

      _updateOperationState(
        operationId,
        result.success
            ? IndexerOperationState.completed
            : IndexerOperationState.error,
        errorMessage: result.success ? null : result.message,
      );

      // Refresh counts after completion
      await loadCounts();

      return result;
    } catch (e) {
      _updateOperationState(operationId, IndexerOperationState.error,
          errorMessage: e.toString());
      return IndexerResult(success: false, message: 'Error: $e');
    }
  }

  /// Cancel the current operation
  void cancelOperation() {
    _currentCancelToken?.cancel();
  }

  void _updateOperationState(String id, IndexerOperationState newState,
      {String? errorMessage}) {
    final operations = Map<String, IndexerOperation>.from(state.operations);
    final op = operations[id];
    if (op != null) {
      operations[id] = op.copyWith(state: newState, errorMessage: errorMessage);
      state = state.copyWith(operations: operations);
    }
  }

  void _updateProgress(String id, int processed, int targetCount) {
    final operations = Map<String, IndexerOperation>.from(state.operations);
    final op = operations[id];
    if (op != null) {
      operations[id] = op.copyWith(processedCount: processed);
      state = state.copyWith(operations: operations);
    }
  }

  void _updateFailedItems(String id, List<String> failedItems) {
    final operations = Map<String, IndexerOperation>.from(state.operations);
    final op = operations[id];
    if (op != null) {
      operations[id] = op.copyWith(
        failedCount: failedItems.length,
        failedItems: failedItems,
      );
      state = state.copyWith(operations: operations);
    }
  }

  Future<IndexerResult> _executeOperation(String operationId,
      {bool force = false}) async {
    final songs = await DatabaseService.instance.getAllSongs();

    switch (operationId) {
      case 'optimize_stats_db':
        return await _optimizeStatsDatabase();
      case 'optimize_user_data_db':
        return await _optimizeUserDataDatabase();
      case 'rebuild_cover_caches':
        return await _rebuildCoverCaches(songs, force: force);
      case 'rebuild_search_indexes':
        return await _rebuildSearchIndexes(songs, force: force);
      case 'rebuild_lyrics_cache':
        return await _rebuildLyricsCache(songs, force: force);
      case 'rebuild_waveform_cache':
        return await _rebuildWaveformCache(songs, force: force);
      case 'rebuild_color_cache':
        return await _rebuildColorCache(songs, force: force);
      default:
        return const IndexerResult(
            success: false, message: 'Unknown operation');
    }
  }

  Future<IndexerResult> _optimizeStatsDatabase() async {
    final optimizer = DatabaseOptimizerService();
    final result = await optimizer.optimizeDatabases(
      options: const OptimizationOptions(
        automaticMode: false,
        selectedTypes: {OptimizationType.statsDatabase},
      ),
    );
    return IndexerResult(
      success: result.success,
      message: result.message,
      warnings: result.issuesFound,
    );
  }

  Future<IndexerResult> _optimizeUserDataDatabase() async {
    final optimizer = DatabaseOptimizerService();
    final result = await optimizer.optimizeDatabases(
      options: const OptimizationOptions(
        automaticMode: false,
        selectedTypes: {OptimizationType.userDataDatabase},
      ),
    );
    return IndexerResult(
      success: result.success,
      message: result.message,
      warnings: result.issuesFound,
    );
  }

  Future<IndexerResult> _rebuildCoverCaches(List<Song> songs,
      {bool force = false}) async {
    int processed = 0;
    final failedItems = <String>[];

    // Pre-calculate target count by checking which songs don't have cached covers
    int targetCount = songs.length;
    if (!force) {
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory('${supportDir.path}/extracted_covers');
      int missingCount = 0;
      for (final song in songs) {
        final file = File(song.url);
        if (await file.exists()) {
          final mtimeMs = song.mtime != null
              ? (song.mtime! * 1000).round()
              : (await file.stat()).modified.millisecondsSinceEpoch;
          final hash = md5.convert(utf8.encode(song.url)).toString();
          bool hasCover = false;
          for (final ext in [
            '.jpg',
            '.png',
            '.jpeg',
            '.webp',
            '.bmp',
            '_ffmpeg.jpg'
          ]) {
            final cachedFile = File('${coversDir.path}/${hash}_$mtimeMs$ext');
            if (await cachedFile.exists()) {
              hasCover = true;
              break;
            }
          }
          if (!hasCover) {
            missingCount++;
          }
        }
      }
      targetCount = missingCount;
    }

    // Update the operation with the correct target count
    final operations = Map<String, IndexerOperation>.from(state.operations);
    final op = operations['rebuild_cover_caches'];
    if (op != null) {
      operations['rebuild_cover_caches'] =
          op.copyWith(targetCount: targetCount);
      state = state.copyWith(operations: operations);
    }

    final scanner = ScannerService();
    final coverMap = await scanner.rebuildCoverCache(
      songs,
      force: force,
      onProgress: (progress) {
        processed = (progress * targetCount).round();
        _updateProgress('rebuild_cover_caches', processed, targetCount);
      },
    );

    // Update database with new cover URLs
    final updatedSongs = <Song>[];
    for (final song in songs) {
      if (_currentCancelToken?.isCancelled ?? false) break;

      try {
        final newCoverUrl = coverMap[song.url];
        if (newCoverUrl != null && newCoverUrl != song.coverUrl) {
          updatedSongs.add(Song(
            title: song.title,
            artist: song.artist,
            album: song.album,
            filename: song.filename,
            url: song.url,
            coverUrl: newCoverUrl,
            hasLyrics: song.hasLyrics,
            playCount: song.playCount,
            duration: song.duration,
            mtime: song.mtime,
          ));
        }
      } catch (e) {
        failedItems.add(song.filename);
      }
    }

    if (updatedSongs.isNotEmpty) {
      await DatabaseService.instance.insertSongsBatch(updatedSongs);
    }

    _updateFailedItems('rebuild_cover_caches', failedItems);

    return IndexerResult(
      success: coverMap.length > 0,
      message: 'Rebuilt covers for ${coverMap.length} songs' +
          (failedItems.isNotEmpty ? ' (${failedItems.length} failed)' : ''),
      warnings: failedItems.isNotEmpty ? failedItems : null,
    );
  }

  Future<IndexerResult> _rebuildSearchIndexes(List<Song> songs,
      {bool force = false}) async {
    final searchService = SearchService();
    await searchService.init();

    try {
      if (force) {
        await searchService.clearIndex();
      }
      await searchService.rebuildIndex(songs);
      final stats = await searchService.getIndexStats();
      final failedCount =
          (songs.length - stats.totalEntries).clamp(0, songs.length) as int;
      final failedItems = failedCount > 0
          ? List<String>.generate(
              failedCount,
              (index) => 'Search index entry ${index + 1} could not be created',
            )
          : <String>[];
      _updateFailedItems('rebuild_search_indexes', failedItems);
      await searchService.dispose();

      return IndexerResult(
        success: true,
        message:
            'Search index rebuilt with ${stats.totalEntries}/${songs.length} entries' +
                (failedCount > 0 ? ' ($failedCount failed)' : ''),
        warnings: failedItems.isNotEmpty ? failedItems : null,
      );
    } catch (e) {
      _updateFailedItems('rebuild_search_indexes', []);
      await searchService.dispose();
      return IndexerResult(
          success: false, message: 'Error rebuilding search index: $e');
    }
  }

  Future<IndexerResult> _rebuildLyricsCache(List<Song> songs,
      {bool force = false}) async {
    int processed = 0;
    int cached = 0;
    int skipped = 0;
    final failedItems = <String>[];

    final repository = SongRepository();

    if (force) {
      await repository.clearLyricsCache();
    }

    // Pre-calculate target count by checking which songs don't have a cache entry
    int targetCount = songs.length;
    if (!force) {
      // Count songs without cache entries
      int missingCount = 0;
      for (final song in songs) {
        if (!await repository.hasLyricsCacheEntry(song)) {
          missingCount++;
        }
      }
      targetCount = missingCount;
    }

    // Update the operation with the correct target count
    final operations = Map<String, IndexerOperation>.from(state.operations);
    final op = operations['rebuild_lyrics_cache'];
    if (op != null) {
      operations['rebuild_lyrics_cache'] =
          op.copyWith(targetCount: targetCount);
      state = state.copyWith(operations: operations);
    }

    for (int i = 0; i < songs.length; i++) {
      if (_currentCancelToken?.isCancelled ?? false) break;

      final song = songs[i];

      try {
        // Check if already cached unless force is true
        // Use hasLyricsCacheEntry to skip songs that have been checked (even if they have no lyrics)
        if (!force) {
          final hasCacheEntry = await repository.hasLyricsCacheEntry(song);
          if (hasCacheEntry) {
            skipped++;
            continue;
          }
        }

        // Extract lyrics
        final lyrics = await repository.getLyrics(song);
        final hasEntry = await repository.hasLyricsCacheEntry(song);
        if (!hasEntry) {
          failedItems.add(song.filename);
        } else if (lyrics != null && lyrics.isNotEmpty) {
          cached++;
        }
        processed++;
        _updateProgress('rebuild_lyrics_cache', processed, targetCount);
      } catch (e) {
        failedItems.add(song.filename);
        processed++;
        _updateProgress('rebuild_lyrics_cache', processed, targetCount);
      }
    }

    _updateFailedItems('rebuild_lyrics_cache', failedItems);

    final message = 'Cached $cached new lyrics' +
        (skipped > 0 ? ', skipped $skipped already cached' : '') +
        (failedItems.isNotEmpty ? ', ${failedItems.length} failed' : '');

    return IndexerResult(
      success: failedItems.length < songs.length / 2,
      message: message,
      warnings: failedItems.isNotEmpty ? failedItems : null,
    );
  }

  Future<IndexerResult> _rebuildWaveformCache(List<Song> songs,
      {bool force = false}) async {
    int processed = 0;
    int cached = 0;
    int skipped = 0;
    final failedItems = <String>[];

    final cacheService = CacheService.instance;
    final waveformService = WaveformService(cacheService);

    // Pre-calculate target count by checking file existence
    int targetCount = songs.length;
    if (!force) {
      int missingCount = 0;
      for (final song in songs) {
        final cacheFile =
            await cacheService.getV3File('waveform_${song.filename}.json');
        if (!await cacheFile.exists()) {
          missingCount++;
        }
      }
      targetCount = missingCount;
    }

    // Update the operation with the correct target count
    final operations = Map<String, IndexerOperation>.from(state.operations);
    final op = operations['rebuild_waveform_cache'];
    if (op != null) {
      operations['rebuild_waveform_cache'] =
          op.copyWith(targetCount: targetCount);
      state = state.copyWith(operations: operations);
    }

    for (int i = 0; i < songs.length; i++) {
      if (_currentCancelToken?.isCancelled ?? false) break;

      final song = songs[i];

      try {
        // Check if already cached unless force is true
        final cacheFile =
            await cacheService.getV3File('waveform_${song.filename}.json');
        if (!force) {
          if (await cacheFile.exists()) {
            skipped++;
            continue;
          }
        } else {
          if (await cacheFile.exists()) {
            await cacheFile.delete();
          }
        }

        // Extract waveform
        final waveform =
            await waveformService.getWaveform(song.filename, song.url);
        if (waveform.isNotEmpty) {
          cached++;
        }
        processed++;
        _updateProgress('rebuild_waveform_cache', processed, targetCount);
      } catch (e) {
        failedItems.add(song.filename);
        processed++;
        _updateProgress('rebuild_waveform_cache', processed, targetCount);
      }
    }

    waveformService.dispose();

    _updateFailedItems('rebuild_waveform_cache', failedItems);

    final message = 'Cached $cached new waveforms' +
        (skipped > 0 ? ', skipped $skipped already cached' : '') +
        (failedItems.isNotEmpty ? ', ${failedItems.length} failed' : '');

    return IndexerResult(
      success: failedItems.length < songs.length / 2,
      message: message,
      warnings: failedItems.isNotEmpty ? failedItems : null,
    );
  }

  Future<IndexerResult> _rebuildColorCache(List<Song> songs,
      {bool force = false}) async {
    int processed = 0;
    int cached = 0;
    int skipped = 0;
    final failedItems = <String>[];

    final imagePaths = songs
        .where((s) => s.coverUrl != null && s.coverUrl!.isNotEmpty)
        .map((s) => s.coverUrl!)
        .toList();

    if (force) {
      await ColorExtractionService.clearCache();
    }

    // Pre-calculate target count by checking which covers don't have cached palettes
    int targetCount = imagePaths.length;
    if (!force) {
      await ColorExtractionService.init();
      int missingCount = 0;
      for (final path in imagePaths) {
        final existing = await ColorExtractionService.extractPalette(path);
        if (existing == null) {
          missingCount++;
        }
      }
      targetCount = missingCount;
    }

    // Update the operation with the correct target count
    final operations = Map<String, IndexerOperation>.from(state.operations);
    final op = operations['rebuild_color_cache'];
    if (op != null) {
      operations['rebuild_color_cache'] = op.copyWith(targetCount: targetCount);
      state = state.copyWith(operations: operations);
    }

    for (int i = 0; i < imagePaths.length; i++) {
      if (_currentCancelToken?.isCancelled ?? false) break;

      final path = imagePaths[i];

      try {
        // Check if already cached unless force is true
        if (!force) {
          final existing = await ColorExtractionService.extractPalette(path);
          if (existing != null) {
            skipped++;
            continue;
          }
        }

        // Extract color palette
        final palette = await ColorExtractionService.extractPalette(path);
        if (palette != null) {
          cached++;
        }
        processed++;
        _updateProgress('rebuild_color_cache', processed, targetCount);
      } catch (e) {
        failedItems.add(path);
        processed++;
        _updateProgress('rebuild_color_cache', processed, targetCount);
      }
    }

    _updateFailedItems('rebuild_color_cache', failedItems);

    final message = 'Extracted $cached color palettes' +
        (skipped > 0 ? ', skipped $skipped already cached' : '') +
        (failedItems.isNotEmpty ? ', ${failedItems.length} failed' : '');

    return IndexerResult(
      success: failedItems.length < imagePaths.length / 2,
      message: message,
      warnings: failedItems.isNotEmpty ? failedItems : null,
    );
  }
}

/// Provider for indexer state
final indexerProvider = NotifierProvider<IndexerNotifier, IndexerState>(() {
  return IndexerNotifier();
});
