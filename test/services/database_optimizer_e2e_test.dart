import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/playlist.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/services/database_optimizer_service.dart';
import 'package:wispie/services/database_service.dart';
import '../test_helpers.dart';

void main() {
  late TestEnvironment testEnv;

  setUpAll(() {
    testEnv = TestEnvironment();
    testEnv.setUp();
  });

  tearDownAll(() {
    testEnv.tearDown();
  });

  setUp(() async {
    await DatabaseService.instance.init();
    await DatabaseService.instance.clearAllPlayStats();
    final db = DatabaseService.instance.getUserDataDatabase();
    if (db != null) {
      await db.delete('song');
      await db.delete('playlist');
      await db.delete('playlist_song');
      await db.delete('favorite');
    }
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  group('DatabaseOptimizerService E2E', () {
    test(
        'optimizes database by deleting short sessions (< 1 min) & their play events while preserving valid sessions, song library, playlists, and favorites',
        () async {
      final dbService = DatabaseService.instance;
      await dbService.ensureInitialized();
      final statsDb = dbService.getStatsDatabase()!;

      // 1. Seed Songs in wispie_data.db
      final song1 = Song(
        title: 'Song One',
        artist: 'Artist Alpha',
        album: 'Album Alpha',
        filename: 'song_one.mp3',
        url: '/music/song_one.mp3',
        duration: const Duration(seconds: 180),
      );
      final song2 = Song(
        title: 'Song Two',
        artist: 'Artist Beta',
        album: 'Album Beta',
        filename: 'song_two.mp3',
        url: '/music/song_two.mp3',
        duration: const Duration(seconds: 240),
      );
      final song3 = Song(
        title: 'Song Three',
        artist: 'Artist Gamma',
        album: 'Album Gamma',
        filename: 'song_three.mp3',
        url: '/music/song_three.mp3',
        duration: const Duration(seconds: 200),
      );
      await dbService.insertSongsBatch([song1, song2, song3]);

      // 2. Seed Playlists & Playlist Songs in wispie_data.db
      final playlist = Playlist(
        id: 'pl_favorites',
        name: 'Favorites List',
        createdAt: 1000.0,
        updatedAt: 1000.0,
        songs: [
          PlaylistSong(
            songFilename: song1.filename,
            addedAt: 1000.0,
          ),
          PlaylistSong(
            songFilename: song2.filename,
            addedAt: 1001.0,
          ),
        ],
      );
      await dbService.savePlaylist(playlist);

      // 3. Seed Favorites in wispie_data.db
      await dbService.addFavorite(song1.filename);
      await dbService.addFavorite(song3.filename);

      // 4. Seed Play Sessions in wispie_stats.db
      // Valid Session A: 300 seconds (5 mins) -> MUST BE PRESERVED
      await statsDb.insert('playsession', {
        'id': 'sess_long_5min',
        'start_time': 10000.0,
        'end_time': 10300.0,
        'platform': 'linux',
        'device_id': 'dev_test',
      });
      await statsDb.insert('playevent', {
        'id': 101,
        'session_id': 'sess_long_5min',
        'song_filename': song1.filename,
        'timestamp': 10000.0,
        'duration_played': 180.0,
        'total_length': 180.0,
        'play_ratio': 1.0,
        'foreground_duration': 180.0,
        'background_duration': 0.0,
      });
      await statsDb.insert('playevent', {
        'id': 102,
        'session_id': 'sess_long_5min',
        'song_filename': song2.filename,
        'timestamp': 10180.0,
        'duration_played': 120.0,
        'total_length': 240.0,
        'play_ratio': 0.5,
        'foreground_duration': 120.0,
        'background_duration': 0.0,
      });

      // Valid Session B: Exact 60 seconds (1 min) -> MUST BE PRESERVED
      await statsDb.insert('playsession', {
        'id': 'sess_exact_60s',
        'start_time': 20000.0,
        'end_time': 20060.0,
        'platform': 'linux',
        'device_id': 'dev_test',
      });
      await statsDb.insert('playevent', {
        'id': 103,
        'session_id': 'sess_exact_60s',
        'song_filename': song3.filename,
        'timestamp': 20000.0,
        'duration_played': 60.0,
        'total_length': 200.0,
        'play_ratio': 0.30,
        'foreground_duration': 60.0,
        'background_duration': 0.0,
      });

      // Short Session C: 15 seconds (< 1 min) -> MUST BE DELETED
      await statsDb.insert('playsession', {
        'id': 'sess_short_15s',
        'start_time': 30000.0,
        'end_time': 30015.0,
        'platform': 'linux',
        'device_id': 'dev_test',
      });
      await statsDb.insert('playevent', {
        'id': 104,
        'session_id': 'sess_short_15s',
        'song_filename': song1.filename,
        'timestamp': 30000.0,
        'duration_played': 15.0,
        'total_length': 180.0,
        'play_ratio': 0.08,
      });

      // Short Session D: 0 seconds (Immediate skip) -> MUST BE DELETED
      await statsDb.insert('playsession', {
        'id': 'sess_short_0s',
        'start_time': 40000.0,
        'end_time': 40000.0,
        'platform': 'linux',
        'device_id': 'dev_test',
      });
      await statsDb.insert('playevent', {
        'id': 105,
        'session_id': 'sess_short_0s',
        'song_filename': song2.filename,
        'timestamp': 40000.0,
        'duration_played': 0.0,
        'total_length': 240.0,
        'play_ratio': 0.0,
      });

      // Short Session E: 59.9 seconds (< 1 min) -> MUST BE DELETED
      await statsDb.insert('playsession', {
        'id': 'sess_short_59s',
        'start_time': 50000.0,
        'end_time': 50059.9,
        'platform': 'linux',
        'device_id': 'dev_test',
      });
      await statsDb.insert('playevent', {
        'id': 106,
        'session_id': 'sess_short_59s',
        'song_filename': song3.filename,
        'timestamp': 50000.0,
        'duration_played': 59.9,
        'total_length': 200.0,
        'play_ratio': 0.29,
      });

      // Invalid Session F: NULL end_time -> MUST BE DELETED
      await statsDb.insert('playsession', {
        'id': 'sess_null_time',
        'start_time': 60000.0,
        'end_time': null,
        'platform': 'linux',
      });
      await statsDb.insert('playevent', {
        'id': 107,
        'session_id': 'sess_null_time',
        'song_filename': song1.filename,
        'timestamp': 60000.0,
        'duration_played': 10.0,
      });

      // Orphaned Play Event: session doesn't exist -> MUST BE DELETED
      await statsDb.insert('playevent', {
        'id': 108,
        'session_id': 'non_existent_session',
        'song_filename': song2.filename,
        'timestamp': 70000.0,
        'duration_played': 45.0,
      });

      // Orphaned Play Event: session_id is null -> MUST BE DELETED
      await statsDb.insert('playevent', {
        'id': 109,
        'session_id': null,
        'song_filename': song3.filename,
        'timestamp': 80000.0,
        'duration_played': 30.0,
      });

      // Verify pre-optimization counts
      final preSessions = await statsDb.query('playsession');
      expect(preSessions.length, 6);
      final preEvents = await statsDb.query('playevent');
      expect(preEvents.length, 9);
      final preSongs = await dbService.getAllSongs();
      expect(preSongs.length, 3);
      final prePlaylists = await dbService.getPlaylists();
      expect(prePlaylists.length, 1);
      final preFavorites = await dbService.getFavorites();
      expect(preFavorites.length, 2);

      // 5. Run Database Optimizer (same as user clicking "Optimize Databases" in UI)
      final optimizer = DatabaseOptimizerService();
      final result = await optimizer.optimizeDatabases(
        options: const OptimizationOptions(
          automaticMode: false,
          selectedTypes: {
            OptimizationType.statsDatabase,
            OptimizationType.userDataDatabase,
          },
        ),
      );

      expect(result.success, isTrue);

      // 6. VERIFY POST-OPTIMIZATION STATE

      // A. Stats Database: Sessions
      final postSessions =
          await statsDb.query('playsession', orderBy: 'id ASC');
      expect(postSessions.length, 2,
          reason: 'Only long session and exact 60s session should remain');
      expect(postSessions.map((s) => s['id']),
          containsAll(['sess_long_5min', 'sess_exact_60s']));
      expect(postSessions.map((s) => s['id']),
          isNot(contains('sess_short_15s')));
      expect(postSessions.map((s) => s['id']),
          isNot(contains('sess_short_0s')));
      expect(postSessions.map((s) => s['id']),
          isNot(contains('sess_short_59s')));
      expect(postSessions.map((s) => s['id']),
          isNot(contains('sess_null_time')));

      // B. Stats Database: Play Events
      final postEvents = await statsDb.query('playevent', orderBy: 'id ASC');
      expect(postEvents.length, 3,
          reason: 'Only playevents from surviving valid sessions should remain');
      final eventIds = postEvents.map((e) => e['id'] as int).toList();
      expect(eventIds, containsAll([101, 102, 103]));
      expect(eventIds, isNot(contains(104)));
      expect(eventIds, isNot(contains(105)));
      expect(eventIds, isNot(contains(106)));
      expect(eventIds, isNot(contains(107)));
      expect(eventIds, isNot(contains(108)));
      expect(eventIds, isNot(contains(109)));

      // Ensure retained events have correct data
      final event101 = postEvents.firstWhere((e) => e['id'] == 101);
      expect(event101['song_filename'], song1.filename);
      expect(event101['session_id'], 'sess_long_5min');
      expect(event101['duration_played'], 180.0);

      final event102 = postEvents.firstWhere((e) => e['id'] == 102);
      expect(event102['song_filename'], song2.filename);
      expect(event102['session_id'], 'sess_long_5min');
      expect(event102['duration_played'], 120.0);

      final event103 = postEvents.firstWhere((e) => e['id'] == 103);
      expect(event103['song_filename'], song3.filename);
      expect(event103['session_id'], 'sess_exact_60s');
      expect(event103['duration_played'], 60.0);

      // C. User Data: Songs MUST NOT be deleted
      final postSongs = await dbService.getAllSongs();
      expect(postSongs.length, 3,
          reason: 'Library songs must be preserved completely');
      expect(postSongs.map((s) => s.filename),
          containsAll([song1.filename, song2.filename, song3.filename]));

      // D. User Data: Playlists MUST NOT be deleted
      final postPlaylists = await dbService.getPlaylists();
      expect(postPlaylists.length, 1);
      expect(postPlaylists.first.name, 'Favorites List');
      expect(postPlaylists.first.songs.length, 2);
      expect(postPlaylists.first.songs.map((s) => s.songFilename),
          containsAll([song1.filename, song2.filename]));

      // E. User Data: Favorites MUST NOT be deleted
      final postFavorites = await dbService.getFavorites();
      expect(postFavorites.length, 2);
      expect(postFavorites, containsAll([song1.filename, song3.filename]));

      // F. Query APIs work accurately post-optimization
      final sessions = await dbService.getPlaySessions(minDurationSeconds: 60);
      expect(sessions.length, 2);

      final playCounts = await dbService.getPlayCounts();
      // event 101 has play_ratio 1.0 > 0.25 -> song1 count: 1
      // event 102 has play_ratio 0.5 > 0.25 -> song2 count: 1
      // event 103 has play_ratio 0.30 > 0.25 -> song3 count: 1
      expect(playCounts[song1.filename], 1);
      expect(playCounts[song2.filename], 1);
      expect(playCounts[song3.filename], 1);
    });
  });
}
