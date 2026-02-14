import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/song.dart';
import '../../services/ffmpeg_service.dart';
import '../models/search_index_entry.dart';

/// Repository for managing the search index database
///
/// The search index is stored in a separate SQLite database file that is
/// explicitly excluded from backups. This allows for fast full-text search
/// across song metadata and lyrics.
class SearchIndexRepository {
  static const String _tableName = 'search_index';
  static const String _metadataTable = 'search_metadata';

  Database? _database;
  String? _currentUsername;
  final FFmpegService _ffmpegService = FFmpegService();

  /// Gets the database file path for a given username
  Future<String> _getDbPath(String username) async {
    final docDir = await getApplicationDocumentsDirectory();
    return join(docDir.path, '${username}_search_index.db');
  }

  /// Initializes the search index database for a user
  Future<void> initForUser(String username) async {
    if (_currentUsername == username && _database != null) return;

    await close();

    final dbPath = await _getDbPath(username);
    _currentUsername = username;

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await _createTables(db);
      },
    );
  }

  /// Creates the necessary tables for the search index
  Future<void> _createTables(Database db) async {
    // Main search index table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        filename TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        lyrics_content TEXT,
        title_length INTEGER NOT NULL DEFAULT 0,
        artist_length INTEGER NOT NULL DEFAULT 0,
        album_length INTEGER NOT NULL DEFAULT 0,
        lyrics_length INTEGER DEFAULT 0,
        last_modified INTEGER NOT NULL
      )
    ''');

    // Metadata table for tracking index stats
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_metadataTable (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // Create indexes for fast searching
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_title ON $_tableName(title)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_artist ON $_tableName(artist)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_album ON $_tableName(album)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_lyrics ON $_tableName(lyrics_content)
    ''');
  }

  /// Rebuilds the entire search index from a list of songs incrementally
  Future<void> rebuildIndex(List<Song> songs) async {
    if (_database == null) {
      throw StateError(
          'SearchIndexRepository not initialized. Call initForUser first.');
    }

    // 1. Fetch existing index state to determine what needs updating
    final List<Map<String, dynamic>> existingEntries = await _database!.query(
      _tableName,
      columns: ['filename', 'last_modified', 'lyrics_content'],
    );

    final Map<String, Map<String, dynamic>> existingMap = {
      for (final entry in existingEntries) entry['filename'] as String: entry
    };

    await _database!.transaction((txn) async {
      final Set<String> newFilenames = songs.map((s) => s.filename).toSet();
      final List<String> toRemove = existingMap.keys
          .where((filename) => !newFilenames.contains(filename))
          .toList();

      // Remove songs no longer in the library
      if (toRemove.isNotEmpty) {
        for (int i = 0; i < toRemove.length; i += 999) {
          final chunk =
              toRemove.sublist(i, (i + 999).clamp(0, toRemove.length));
          await txn.delete(
            _tableName,
            where: 'filename IN (${chunk.map((_) => '?').join(',')})',
            whereArgs: chunk,
          );
        }
      }

      // Batch update/insert all songs
      final batch = txn.batch();
      int updateCount = 0;

      for (final song in songs) {
        final existing = existingMap[song.filename];
        final int songMtime =
            (song.mtime != null) ? (song.mtime! * 1000).round() : 0;
        final int existingMtime = (existing?['last_modified'] as int?) ?? -1;

        String? lyricsContent;

        // Optimization: Skip extraction if file hasn't changed OR reuse cached lyrics
        if (existing != null && songMtime == existingMtime) {
          // Metadata and mtime match, we can skip this entirely unless we want to ensure
          // lyrics are still there. But for speed, we skip.
          continue;
        }

        updateCount++;

        // Reuse lyrics if available, otherwise extract if song has them
        if (existing != null && existing['lyrics_content'] != null) {
          lyricsContent = existing['lyrics_content'] as String;
        } else if (song.hasLyrics) {
          try {
            final lyrics = await _ffmpegService.getLyrics(song.url);
            if (lyrics != null && lyrics.isNotEmpty) {
              lyricsContent = LyricLine.extractPlainText(lyrics).toLowerCase();
            }
          } catch (e) {
            debugPrint('Error reading lyrics for ${song.filename}: $e');
          }
        }

        batch.insert(
          _tableName,
          {
            'filename': song.filename,
            'title': song.title.toLowerCase(),
            'artist': song.artist.toLowerCase(),
            'album': song.album.toLowerCase(),
            'lyrics_content': lyricsContent,
            'title_length': song.title.length,
            'artist_length': song.artist.length,
            'album_length': song.album.length,
            'lyrics_length': lyricsContent?.length ?? 0,
            'last_modified': songMtime,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (updateCount > 0) {
        await batch.commit(noResult: true);
      }

      // Update metadata
      await txn.insert(
        _metadataTable,
        {
          'key': 'last_updated',
          'value': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        _metadataTable,
        {
          'key': 'total_entries',
          'value': songs.length.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    // Only vacuum if significant changes occurred (e.g. library cleared or many removals)
    // VACUUM is expensive and shouldn't run on every refresh.
  }

  /// Updates or inserts a single song into the index
  Future<void> upsertSong(Song song) async {
    if (_database == null) return;

    final int songMtime =
        (song.mtime != null) ? (song.mtime! * 1000).round() : 0;

    // Check if we already have lyrics for this file to avoid re-extraction
    String? lyricsContent;
    final existing = await _database!.query(
      _tableName,
      columns: ['lyrics_content'],
      where: 'filename = ?',
      whereArgs: [song.filename],
    );

    if (existing.isNotEmpty && existing.first['lyrics_content'] != null) {
      lyricsContent = existing.first['lyrics_content'] as String;
    } else if (song.hasLyrics) {
      try {
        final lyrics = await _ffmpegService.getLyrics(song.url);
        if (lyrics != null && lyrics.isNotEmpty) {
          lyricsContent = LyricLine.extractPlainText(lyrics).toLowerCase();
        }
      } catch (e) {
        debugPrint('Error reading lyrics for ${song.filename}: $e');
      }
    }

    await _database!.insert(
      _tableName,
      {
        'filename': song.filename,
        'title': song.title.toLowerCase(),
        'artist': song.artist.toLowerCase(),
        'album': song.album.toLowerCase(),
        'lyrics_content': lyricsContent,
        'title_length': song.title.length,
        'artist_length': song.artist.length,
        'album_length': song.album.length,
        'lyrics_length': lyricsContent?.length ?? 0,
        'last_modified': songMtime,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes a song from the index
  Future<void> removeSong(String filename) async {
    if (_database == null) return;

    await _database!.delete(
      _tableName,
      where: 'filename = ?',
      whereArgs: [filename],
    );
  }

  /// Searches for songs matching the query in specified fields
  ///
  /// Returns a list of filenames that match the search criteria
  Future<List<SearchMatch>> search({
    required String query,
    required bool searchTitles,
    required bool searchArtists,
    required bool searchAlbums,
    required bool searchLyrics,
  }) async {
    if (_database == null || query.isEmpty) {
      return [];
    }

    final lowerQuery = query.toLowerCase();
    final results = <SearchMatch>[];
    final seenFilenames = <String>{};

    // Search titles
    if (searchTitles) {
      final titleResults = await _database!.query(
        _tableName,
        columns: ['filename', 'title'],
        where: 'title LIKE ?',
        whereArgs: ['%$lowerQuery%'],
      );
      for (final row in titleResults) {
        final filename = row['filename'] as String;
        if (seenFilenames.add(filename)) {
          results.add(SearchMatch(
            filename: filename,
            matchType: SearchMatchType.title,
            matchedText: _extractMatchText(row['title'] as String, lowerQuery),
          ));
        }
      }
    }

    // Search artists
    if (searchArtists) {
      final artistResults = await _database!.query(
        _tableName,
        columns: ['filename', 'artist'],
        where: 'artist LIKE ?',
        whereArgs: ['%$lowerQuery%'],
      );
      for (final row in artistResults) {
        final filename = row['filename'] as String;
        if (seenFilenames.add(filename)) {
          results.add(SearchMatch(
            filename: filename,
            matchType: SearchMatchType.artist,
            matchedText: _extractMatchText(row['artist'] as String, lowerQuery),
          ));
        }
      }
    }

    // Search albums
    if (searchAlbums) {
      final albumResults = await _database!.query(
        _tableName,
        columns: ['filename', 'album'],
        where: 'album LIKE ?',
        whereArgs: ['%$lowerQuery%'],
      );
      for (final row in albumResults) {
        final filename = row['filename'] as String;
        if (seenFilenames.add(filename)) {
          results.add(SearchMatch(
            filename: filename,
            matchType: SearchMatchType.album,
            matchedText: _extractMatchText(row['album'] as String, lowerQuery),
          ));
        }
      }
    }

    // Search lyrics
    if (searchLyrics) {
      final lyricsResults = await _database!.query(
        _tableName,
        columns: ['filename', 'lyrics_content'],
        where: 'lyrics_content LIKE ?',
        whereArgs: ['%$lowerQuery%'],
      );
      for (final row in lyricsResults) {
        final filename = row['filename'] as String;
        final lyrics = row['lyrics_content'] as String?;
        if (lyrics != null) {
          final match = _findLyricsMatch(lyrics, lowerQuery);
          if (match != null) {
            // Remove from seen if already exists (lyrics match takes priority for display)
            seenFilenames.remove(filename);
            results.removeWhere((r) => r.filename == filename);
            results.add(SearchMatch(
              filename: filename,
              matchType: SearchMatchType.lyrics,
              matchedText: match.matchedText,
              fullLine: match.fullLine,
            ));
            seenFilenames.add(filename);
          }
        }
      }
    }

    return results;
  }

  /// Extracts the matching portion of text with surrounding context
  String _extractMatchText(String text, String query) {
    final index = text.indexOf(query);
    if (index == -1) return text;

    // Return the matched portion
    return query;
  }

  /// Finds the lyrics match with context
  /// Returns the plain text line without timestamps for display
  LyricsMatchResult? _findLyricsMatch(String lyrics, String query) {
    final lines = lyrics.split('\n');
    for (final line in lines) {
      if (line.contains(query)) {
        // Remove timestamps from the display line
        final plainLine = _removeTimestamps(line.trim());
        return LyricsMatchResult(
          matchedText: query,
          fullLine: plainLine,
        );
      }
    }
    return null;
  }

  /// Removes LRC timestamps from a line
  String _removeTimestamps(String line) {
    // Match timestamp format [mm:ss.xx] or [mm:ss.xxx] or [mm:ss]
    final timestampExp = RegExp(r'\[([0-9]+):([0-9]+\.?[0-9]*)\]');
    return line.replaceAll(timestampExp, '').trim();
  }

  /// Gets statistics about the search index
  Future<SearchIndexStats> getStats() async {
    if (_database == null) {
      return SearchIndexStats.empty();
    }

    final countResult =
        await _database!.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
    final totalEntries = Sqflite.firstIntValue(countResult) ?? 0;

    final lyricsCountResult = await _database!.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName WHERE lyrics_content IS NOT NULL');
    final entriesWithLyrics = Sqflite.firstIntValue(lyricsCountResult) ?? 0;

    final lyricsLengthResult = await _database!
        .rawQuery('SELECT SUM(lyrics_length) as total FROM $_tableName');
    final totalLyricsChars =
        (lyricsLengthResult.first['total'] as num?)?.toInt() ?? 0;

    final metadataResult = await _database!.query(
      _metadataTable,
      where: 'key = ?',
      whereArgs: ['last_updated'],
    );
    DateTime? lastUpdated;
    if (metadataResult.isNotEmpty) {
      final timestamp = int.tryParse(metadataResult.first['value'] as String);
      if (timestamp != null) {
        lastUpdated = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    }

    return SearchIndexStats(
      totalEntries: totalEntries,
      entriesWithLyrics: entriesWithLyrics,
      totalLyricsChars: totalLyricsChars,
      lastUpdated: lastUpdated,
    );
  }

  /// Clears the entire search index
  Future<void> clear() async {
    if (_database == null) return;

    await _database!.transaction((txn) async {
      await txn.delete(_tableName);
      await txn.delete(_metadataTable);
    });
  }

  /// Closes the database connection
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Gets the database file path (for backup exclusion)
  Future<String?> getDatabaseFilePath(String username) async {
    final path = await _getDbPath(username);
    final file = File(path);
    if (await file.exists()) {
      return path;
    }
    return null;
  }

  /// Deletes the search index database file
  Future<void> deleteDatabaseFile(String username) async {
    final path = await _getDbPath(username);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Represents a search match result
class SearchMatch {
  final String filename;
  final SearchMatchType matchType;
  final String matchedText;
  final String? fullLine;

  const SearchMatch({
    required this.filename,
    required this.matchType,
    required this.matchedText,
    this.fullLine,
  });
}

/// Type of search match
enum SearchMatchType {
  title,
  artist,
  album,
  lyrics,
}

/// Internal class for lyrics match results
class LyricsMatchResult {
  final String matchedText;
  final String fullLine;

  LyricsMatchResult({
    required this.matchedText,
    required this.fullLine,
  });
}
