import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// Result of a database optimization operation
class OptimizationResult {
  final bool success;
  final String message;
  final Map<String, dynamic> details;
  final List<String> issuesFound;
  final List<String> fixesApplied;

  OptimizationResult({
    required this.success,
    required this.message,
    this.details = const {},
    this.issuesFound = const [],
    this.fixesApplied = const [],
  });
}

/// Service for optimizing and repairing database files
/// 
/// This service handles database maintenance tasks:
/// - Vacuum databases to reclaim space
/// - Fix orphaned records
/// - Remove duplicate entries
/// - Ensure table schemas are up to date (without data loss)
class DatabaseOptimizerService {
  static final DatabaseOptimizerService _instance = DatabaseOptimizerService._internal();
  factory DatabaseOptimizerService() => _instance;
  DatabaseOptimizerService._internal();

  /// Analyzes and optimizes all database files for a user
  Future<OptimizationResult> optimizeDatabases(String username) async {
    final issuesFound = <String>[];
    final fixesApplied = <String>[];
    final details = <String, dynamic>{};

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final statsDbPath = join(docDir.path, '${username}_stats.db');
      final userDataDbPath = join(docDir.path, '${username}_data.db');

      // Optimize stats database (just vacuum, don't modify schema)
      final statsResult = await _optimizeStatsDatabase(statsDbPath);
      issuesFound.addAll(statsResult['issues'] as List<String>);
      fixesApplied.addAll(statsResult['fixes'] as List<String>);
      details['stats_db'] = statsResult['details'];

      // Optimize user data database (fix schema, orphans, duplicates)
      final userDataResult = await _optimizeUserDataDatabase(userDataDbPath);
      issuesFound.addAll(userDataResult['issues'] as List<String>);
      fixesApplied.addAll(userDataResult['fixes'] as List<String>);
      details['user_data_db'] = userDataResult['details'];

      final success = issuesFound.isEmpty || fixesApplied.isNotEmpty;
      final message = success
          ? 'Database optimization completed successfully. ${fixesApplied.length} fixes applied.'
          : 'Database optimization found issues but could not fix all of them.';

      return OptimizationResult(
        success: success,
        message: message,
        details: details,
        issuesFound: issuesFound,
        fixesApplied: fixesApplied,
      );
    } catch (e) {
      return OptimizationResult(
        success: false,
        message: 'Database optimization failed: $e',
        issuesFound: issuesFound,
        fixesApplied: fixesApplied,
        details: details,
      );
    }
  }

  /// Optimizes the stats database (playevent table)
  /// Only vacuums - doesn't modify schema to avoid data loss
  Future<Map<String, dynamic>> _optimizeStatsDatabase(String dbPath) async {
    final issues = <String>[];
    final fixes = <String>[];
    final details = <String, dynamic>{};

    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      // Stats database doesn't exist yet, nothing to optimize
      details['exists'] = false;
      return {'issues': issues, 'fixes': fixes, 'details': details};
    }

    try {
      final db = await openDatabase(dbPath);

      // Run integrity check
      final integrityCheck = await db.rawQuery('PRAGMA integrity_check');
      final isOk = integrityCheck.first.values.first == 'ok';

      if (!isOk) {
        issues.add('Stats database integrity check failed');
        // For stats, we just report it - don't try to fix as it might lose data
        fixes.add('Stats database integrity issues detected (manual intervention may be needed)');
      }

      // Vacuum to reclaim space
      await db.execute('VACUUM');
      fixes.add('Vacuumed stats database');

      await db.close();
      details['vacuumed'] = true;
    } catch (e) {
      issues.add('Error optimizing stats database: $e');
    }

    return {'issues': issues, 'fixes': fixes, 'details': details};
  }

  /// Optimizes the user data database
  /// Fixes schema issues, removes orphans and duplicates
  Future<Map<String, dynamic>> _optimizeUserDataDatabase(String dbPath) async {
    final issues = <String>[];
    final fixes = <String>[];
    final details = <String, dynamic>{};

    // Check if database file exists
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      // Create new database with proper schema
      final db = await openDatabase(dbPath, version: 1);
      await _createUserDataSchema(db);
      await db.close();
      fixes.add('Created new user data database with proper schema');
      details['created_new'] = true;
      return {'issues': issues, 'fixes': fixes, 'details': details};
    }

    Database? db;
    try {
      db = await openDatabase(dbPath);

      // Run integrity check
      final integrityCheck = await db.rawQuery('PRAGMA integrity_check');
      final isOk = integrityCheck.first.values.first == 'ok';

      if (!isOk) {
        issues.add('User data database integrity check failed');
        await db.close();
        // Recover by backing up and creating new
        await _recoverCorruptedUserDataDatabase(dbPath);
        fixes.add('Recovered corrupted user data database (backup created)');
        details['recovered'] = true;
        return {'issues': issues, 'fixes': fixes, 'details': details};
      }

      // Step 1: Ensure all tables exist (create missing ones)
      final tableResult = await _ensureUserDataTables(db);
      issues.addAll(tableResult['issues'] as List<String>);
      fixes.addAll(tableResult['fixes'] as List<String>);
      details['tables'] = tableResult['details'];

      // Step 2: Ensure all columns exist (add missing ones)
      final columnResult = await _ensureUserDataColumns(db);
      issues.addAll(columnResult['issues'] as List<String>);
      fixes.addAll(columnResult['fixes'] as List<String>);
      details['columns'] = columnResult['details'];

      // Step 3: Create indexes (after tables are guaranteed to exist)
      final indexResult = await _ensureUserDataIndexes(db);
      issues.addAll(indexResult['issues'] as List<String>);
      fixes.addAll(indexResult['fixes'] as List<String>);
      details['indexes'] = indexResult['details'];

      // Step 4: Fix orphaned records
      final orphanResult = await _fixOrphanedRecords(db);
      if (orphanResult['issuesFound'] > 0) {
        issues.add('Found ${orphanResult['issuesFound']} orphaned records');
        fixes.add('Removed ${orphanResult['issuesFixed']} orphaned records');
      }
      details['orphaned_records'] = orphanResult;

      // Step 5: Fix duplicate entries
      final duplicateResult = await _fixDuplicates(db);
      if (duplicateResult['issuesFound'] > 0) {
        issues.add('Found ${duplicateResult['issuesFound']} duplicate entries');
        fixes.add('Removed ${duplicateResult['issuesFixed']} duplicate entries');
      }
      details['duplicates'] = duplicateResult;

      // Step 6: Vacuum
      await db.execute('VACUUM');
      fixes.add('Vacuumed user data database');

      await db.close();
    } catch (e) {
      issues.add('Error optimizing user data database: $e');
      try {
        await db?.close();
      } catch (_) {}
    }

    return {'issues': issues, 'fixes': fixes, 'details': details};
  }

  /// Creates the full schema for user data database
  Future<void> _createUserDataSchema(Database db) async {
    // favorite table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorite (
        filename TEXT PRIMARY KEY,
        added_at REAL
      )
    ''');

    // suggestless table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suggestless (
        filename TEXT PRIMARY KEY,
        added_at REAL
      )
    ''');

    // hidden table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hidden (
        filename TEXT PRIMARY KEY,
        hidden_at REAL
      )
    ''');

    // playlist table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlist (
        id TEXT PRIMARY KEY,
        name TEXT,
        created_at REAL,
        updated_at REAL
      )
    ''');

    // playlist_song table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_song (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id TEXT,
        song_filename TEXT,
        added_at REAL,
        FOREIGN KEY (playlist_id) REFERENCES playlist (id)
      )
    ''');

    // merged_song_group table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS merged_song_group (
        id TEXT PRIMARY KEY,
        priority_filename TEXT,
        created_at REAL
      )
    ''');

    // merged_song table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS merged_song (
        filename TEXT PRIMARY KEY,
        group_id TEXT,
        added_at REAL,
        FOREIGN KEY (group_id) REFERENCES merged_song_group (id) ON DELETE CASCADE
      )
    ''');
  }

  /// Ensures all user data tables exist
  Future<Map<String, dynamic>> _ensureUserDataTables(Database db) async {
    final issues = <String>[];
    final fixes = <String>[];
    final details = <String, dynamic>{};

    final tables = [
      'favorite',
      'suggestless',
      'hidden',
      'playlist',
      'playlist_song',
      'merged_song_group',
      'merged_song',
    ];

    for (final tableName in tables) {
      final tableInfo = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [tableName],
      );

      if (tableInfo.isEmpty) {
        issues.add('Table $tableName is missing');
        // Create just this table
        await _createSingleTable(db, tableName);
        fixes.add('Created missing table $tableName');
        details[tableName] = {'created': true};
      } else {
        details[tableName] = {'exists': true};
      }
    }

    return {'issues': issues, 'fixes': fixes, 'details': details};
  }

  /// Creates a single table by name
  Future<void> _createSingleTable(Database db, String tableName) async {
    switch (tableName) {
      case 'favorite':
        await db.execute('''
          CREATE TABLE IF NOT EXISTS favorite (
            filename TEXT PRIMARY KEY,
            added_at REAL
          )
        ''');
        break;
      case 'suggestless':
        await db.execute('''
          CREATE TABLE IF NOT EXISTS suggestless (
            filename TEXT PRIMARY KEY,
            added_at REAL
          )
        ''');
        break;
      case 'hidden':
        await db.execute('''
          CREATE TABLE IF NOT EXISTS hidden (
            filename TEXT PRIMARY KEY,
            hidden_at REAL
          )
        ''');
        break;
      case 'playlist':
        await db.execute('''
          CREATE TABLE IF NOT EXISTS playlist (
            id TEXT PRIMARY KEY,
            name TEXT,
            created_at REAL,
            updated_at REAL
          )
        ''');
        break;
      case 'playlist_song':
        await db.execute('''
          CREATE TABLE IF NOT EXISTS playlist_song (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            playlist_id TEXT,
            song_filename TEXT,
            added_at REAL,
            FOREIGN KEY (playlist_id) REFERENCES playlist (id)
          )
        ''');
        break;
      case 'merged_song_group':
        await db.execute('''
          CREATE TABLE IF NOT EXISTS merged_song_group (
            id TEXT PRIMARY KEY,
            priority_filename TEXT,
            created_at REAL
          )
        ''');
        break;
      case 'merged_song':
        await db.execute('''
          CREATE TABLE IF NOT EXISTS merged_song (
            filename TEXT PRIMARY KEY,
            group_id TEXT,
            added_at REAL,
            FOREIGN KEY (group_id) REFERENCES merged_song_group (id) ON DELETE CASCADE
          )
        ''');
        break;
    }
  }

  /// Ensures all columns exist in user data tables
  Future<Map<String, dynamic>> _ensureUserDataColumns(Database db) async {
    final issues = <String>[];
    final fixes = <String>[];
    final details = <String, dynamic>{};

    // Define expected columns for each table
    final expectedColumns = <String, List<Map<String, dynamic>>>{
      'merged_song_group': [
        {'name': 'id', 'type': 'TEXT'},
        {'name': 'priority_filename', 'type': 'TEXT'},
        {'name': 'created_at', 'type': 'REAL'},
      ],
    };

    for (final entry in expectedColumns.entries) {
      final tableName = entry.key;
      final columns = entry.value;

      // Get existing columns
      final existingCols = await db.rawQuery('PRAGMA table_info($tableName)');
      final existingNames = existingCols.map((c) => c['name'] as String).toSet();

      for (final col in columns) {
        final colName = col['name'] as String;
        if (!existingNames.contains(colName)) {
          issues.add('Table $tableName is missing column $colName');
          try {
            final colType = col['type'] as String;
            await db.execute('ALTER TABLE $tableName ADD COLUMN $colName $colType');
            fixes.add('Added column $colName to $tableName');
          } catch (e) {
            issues.add('Failed to add column $colName to $tableName: $e');
          }
        }
      }
    }

    return {'issues': issues, 'fixes': fixes, 'details': details};
  }

  /// Ensures all indexes exist (call AFTER ensuring tables exist)
  Future<Map<String, dynamic>> _ensureUserDataIndexes(Database db) async {
    final issues = <String>[];
    final fixes = <String>[];
    final details = <String, dynamic>{};

    // Get existing indexes
    final existingIndexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    );
    final indexNames = existingIndexes.map((i) => i['name'] as String).toSet();

    // Define expected indexes - only for tables in user_data.db
    final expectedIndexes = <String, String>{
      'idx_merged_song_group_id': 'CREATE INDEX idx_merged_song_group_id ON merged_song(group_id)',
      'idx_playlist_song_playlist_id': 'CREATE INDEX idx_playlist_song_playlist_id ON playlist_song(playlist_id)',
    };

    for (final entry in expectedIndexes.entries) {
      final indexName = entry.key;
      final createSql = entry.value;

      if (!indexNames.contains(indexName)) {
        issues.add('Index $indexName is missing');
        try {
          await db.execute(createSql);
          fixes.add('Created missing index $indexName');
        } catch (e) {
          // Don't report as issue if table doesn't exist (shouldn't happen)
          if (!e.toString().contains('no such table')) {
            issues.add('Failed to create index $indexName: $e');
          }
        }
      }
    }

    details['indexes_checked'] = expectedIndexes.length;
    return {'issues': issues, 'fixes': fixes, 'details': details};
  }

  /// Fixes orphaned records
  Future<Map<String, dynamic>> _fixOrphanedRecords(Database db) async {
    int issuesFound = 0;
    int issuesFixed = 0;

    try {
      // Check for orphaned playlist_song records
      final orphanedSongs = await db.rawQuery('''
        SELECT ps.id FROM playlist_song ps
        LEFT JOIN playlist p ON ps.playlist_id = p.id
        WHERE p.id IS NULL
      ''');

      if (orphanedSongs.isNotEmpty) {
        issuesFound += orphanedSongs.length;
        for (final row in orphanedSongs) {
          final id = row['id'];
          await db.delete('playlist_song', where: 'id = ?', whereArgs: [id]);
        }
        issuesFixed += orphanedSongs.length;
      }

      // Check for orphaned merged_song records
      final orphanedMerged = await db.rawQuery('''
        SELECT ms.filename FROM merged_song ms
        LEFT JOIN merged_song_group msg ON ms.group_id = msg.id
        WHERE msg.id IS NULL
      ''');

      if (orphanedMerged.isNotEmpty) {
        issuesFound += orphanedMerged.length;
        for (final row in orphanedMerged) {
          final filename = row['filename'] as String;
          await db.delete('merged_song', where: 'filename = ?', whereArgs: [filename]);
        }
        issuesFixed += orphanedMerged.length;
      }
    } catch (e) {
      debugPrint('Error fixing orphaned records: $e');
    }

    return {
      'issuesFound': issuesFound,
      'issuesFixed': issuesFixed,
    };
  }

  /// Fixes duplicate entries
  Future<Map<String, dynamic>> _fixDuplicates(Database db) async {
    int issuesFound = 0;
    int issuesFixed = 0;

    try {
      // Fix duplicate favorites (keep most recent)
      final dupFavorites = await db.rawQuery('''
        SELECT filename, COUNT(*) as cnt, MAX(added_at) as max_time
        FROM favorite
        GROUP BY filename
        HAVING cnt > 1
      ''');

      for (final dup in dupFavorites) {
        final filename = dup['filename'] as String;
        final maxTime = dup['max_time'] as double?;
        
        if (maxTime != null) {
          final deleted = await db.delete(
            'favorite',
            where: 'filename = ? AND added_at < ?',
            whereArgs: [filename, maxTime],
          );
          
          issuesFound += (dup['cnt'] as int) - 1;
          issuesFixed += deleted;
        }
      }

      // Fix duplicate suggestless entries
      final dupSuggestless = await db.rawQuery('''
        SELECT filename, COUNT(*) as cnt, MAX(added_at) as max_time
        FROM suggestless
        GROUP BY filename
        HAVING cnt > 1
      ''');

      for (final dup in dupSuggestless) {
        final filename = dup['filename'] as String;
        final maxTime = dup['max_time'] as double?;
        
        if (maxTime != null) {
          final deleted = await db.delete(
            'suggestless',
            where: 'filename = ? AND added_at < ?',
            whereArgs: [filename, maxTime],
          );
          
          issuesFound += (dup['cnt'] as int) - 1;
          issuesFixed += deleted;
        }
      }
    } catch (e) {
      debugPrint('Error fixing duplicates: $e');
    }

    return {
      'issuesFound': issuesFound,
      'issuesFixed': issuesFixed,
    };
  }

  /// Recovers a corrupted user data database by backing it up and creating a new one
  Future<void> _recoverCorruptedUserDataDatabase(String dbPath) async {
    // Backup the corrupted file
    final backupPath = '$dbPath.corrupted.${DateTime.now().millisecondsSinceEpoch}';
    await File(dbPath).rename(backupPath);

    // Create new database with proper schema
    final db = await openDatabase(dbPath, version: 1);
    await _createUserDataSchema(db);
    await db.close();

    debugPrint('Recovered user data database. Corrupted file backed up to $backupPath');
  }
}
