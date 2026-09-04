import 'package:sqflite/sqflite.dart';

const int kStatsDbVersion = 1;
const int kUserDataDbVersion = 2;

const List<String> _statsTableStmts = [
  '''
    CREATE TABLE IF NOT EXISTS playsession (
      id TEXT PRIMARY KEY,
      start_time REAL,
      end_time REAL,
      platform TEXT,
      device_id TEXT
    )''',
  '''
    CREATE TABLE IF NOT EXISTS playevent (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT,
      song_filename TEXT,
      timestamp REAL,
      duration_played REAL,
      total_length REAL,
      play_ratio REAL,
      foreground_duration REAL,
      background_duration REAL,
      FOREIGN KEY (session_id) REFERENCES playsession (id)
    )''',
];

const List<String> _userDataTableStmts = [
  '''
    CREATE TABLE IF NOT EXISTS userdata (
      username TEXT PRIMARY KEY,
      password_hash TEXT,
      created_at REAL
    )''',
  'CREATE TABLE IF NOT EXISTS favorite (filename TEXT PRIMARY KEY, added_at REAL)',
  'CREATE TABLE IF NOT EXISTS suggestless (filename TEXT PRIMARY KEY, added_at REAL)',
  'CREATE TABLE IF NOT EXISTS hidden (filename TEXT PRIMARY KEY, hidden_at REAL)',
  'CREATE TABLE IF NOT EXISTS cover_miss (filename TEXT PRIMARY KEY, file_mtime REAL, checked_at REAL)',
  '''
    CREATE TABLE IF NOT EXISTS song (
      filename TEXT PRIMARY KEY,
      title TEXT,
      artist TEXT,
      album TEXT,
      url TEXT,
      cover_url TEXT,
      has_lyrics INTEGER,
      play_count INTEGER,
      duration_ms INTEGER,
      mtime REAL,
      created_epoch_sec REAL,
      song_date_epoch_sec REAL
    )''',
  '''
    CREATE TABLE IF NOT EXISTS playlist (
      id TEXT PRIMARY KEY,
      name TEXT,
      description TEXT,
      is_recommendation INTEGER DEFAULT 0,
      created_at REAL,
      updated_at REAL
    )''',
  '''
    CREATE TABLE IF NOT EXISTS playlist_song (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      playlist_id TEXT,
      song_filename TEXT,
      added_at REAL,
      FOREIGN KEY (playlist_id) REFERENCES playlist (id)
    )''',
  '''
    CREATE TABLE IF NOT EXISTS merged_song_group (
      id TEXT PRIMARY KEY,
      priority_filename TEXT,
      created_at REAL
    )''',
  '''
    CREATE TABLE IF NOT EXISTS merged_song (
      filename TEXT PRIMARY KEY,
      group_id TEXT,
      added_at REAL,
      FOREIGN KEY (group_id) REFERENCES merged_song_group (id) ON DELETE CASCADE
    )''',
  '''
    CREATE TABLE IF NOT EXISTS recommendation_preference (
      id TEXT PRIMARY KEY,
      custom_title TEXT,
      is_pinned INTEGER DEFAULT 0,
      updated_at REAL
    )''',
  'CREATE TABLE IF NOT EXISTS recommendation_removal (id TEXT PRIMARY KEY, removed_at REAL)',
  '''
    CREATE TABLE IF NOT EXISTS queue_snapshot (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      created_at REAL NOT NULL,
      source TEXT NOT NULL,
      song_count INTEGER NOT NULL DEFAULT 0
    )''',
  '''
    CREATE TABLE IF NOT EXISTS queue_snapshot_song (
      snapshot_id TEXT NOT NULL,
      song_filename TEXT NOT NULL,
      position INTEGER NOT NULL,
      PRIMARY KEY (snapshot_id, position),
      FOREIGN KEY (snapshot_id) REFERENCES queue_snapshot (id) ON DELETE CASCADE
    )''',
  '''
    CREATE TABLE IF NOT EXISTS artist_art (
      artist_name TEXT PRIMARY KEY,
      image_url TEXT,
      local_path TEXT,
      source TEXT,
      updated_at REAL
    )''',
  '''
    CREATE TABLE IF NOT EXISTS album_art (
      album_key TEXT PRIMARY KEY,
      album_name TEXT,
      artist_name TEXT,
      image_url TEXT,
      local_path TEXT,
      source TEXT,
      updated_at REAL
    )''',
  '''
    CREATE TABLE IF NOT EXISTS translated_lyrics (
      filename TEXT,
      target_lang TEXT,
      translated_content TEXT,
      source_hash TEXT,
      updated_at REAL,
      PRIMARY KEY (filename, target_lang)
    )''',
];

// Kept for tests and debugging that join the schema.
String get kStatsSchema => '${_statsTableStmts.join(';\n')};';
String get kUserDataSchemaV2 => '${_userDataTableStmts.join(';\n')};';

Future<void> _createAllUserDataTables(Database db) async {
  for (final stmt in _userDataTableStmts) {
    await db.execute(stmt);
  }
}

Future<void> _createAllStatsTables(Database db) async {
  for (final stmt in _statsTableStmts) {
    await db.execute(stmt);
  }
}

Future<void> createUserDataSchema(Database db) async {
  await _createAllUserDataTables(db);
  await _createUserDataIndexes(db);
  await _ensureTranslatedLyricsSourceHash(db);
}

Future<void> createStatsSchema(Database db) async {
  await _createAllStatsTables(db);
}

Future<void> upgradeUserDataFrom1To2(Database db) async {
  await _createAllUserDataTables(db);
  await _ensureSongMissingColumns(db);
  await _createUserDataIndexes(db);
  await _ensureTranslatedLyricsSourceHash(db);
}

Future<void> _ensureSongMissingColumns(Database db) async {
  final cols = await db.rawQuery('PRAGMA table_info(song)');
  final names = {for (final c in cols) c['name'] as String};
  Future<void> addIfMissing(String col, String type) async {
    if (!names.contains(col)) {
      await db.execute('ALTER TABLE song ADD COLUMN $col $type');
    }
  }

  await addIfMissing('created_epoch_sec', 'REAL');
  await addIfMissing('song_date_epoch_sec', 'REAL');
}

Future<void> _createUserDataIndexes(Database db) async {
  await db
      .execute('CREATE INDEX IF NOT EXISTS idx_song_artist ON song(artist)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_song_album ON song(album)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_song_mtime ON song(mtime)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_song_created_epoch_sec ON song(created_epoch_sec)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_song_date_epoch_sec ON song(song_date_epoch_sec)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_queue_snapshot_created_at ON queue_snapshot(created_at)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_queue_snapshot_song_snapshot_id ON queue_snapshot_song(snapshot_id)');
}

Future<void> _ensureTranslatedLyricsSourceHash(Database db) async {
  final cols = await db.rawQuery('PRAGMA table_info(translated_lyrics)');
  if (!cols.any((c) => c['name'] == 'source_hash')) {
    await db
        .execute('ALTER TABLE translated_lyrics ADD COLUMN source_hash TEXT');
  }
}
