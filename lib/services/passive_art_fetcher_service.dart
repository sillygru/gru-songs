import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../providers/artist_album_art_provider.dart';
import '../providers/providers.dart';
import 'online_metadata_service.dart';

/// Passively fetches missing artist and album artwork while the app is foregrounded.
///
/// Artwork lookups are the app's biggest background data consumer — Last.fm
/// lookups download entire HTML pages — so this service is careful about how
/// often it re-searches:
/// * every actual lookup attempt is persisted, so a miss is a miss until the
///   user clears art or removes it, instead of being re-queried on every
///   launch and every foreground resume;
/// * the silent full-library sweep runs at most once per day. Requests made
///   while the user actually browses an artist/album still run immediately.
///
/// Attempt bookkeeping is split in two:
/// * the in-memory sets suppress re-attempts within the current process
///   (including after `setArtistArt`/`removeArtistArt`, exactly as before);
/// * the persisted lists stop cross-session re-searches of lookup misses.
///   Deltas are queued separately (adds from lookup attempts, removes from
///   art removal) and flushed on a debounce, so one cannot clobber the other.
class PassiveArtFetcherService with WidgetsBindingObserver {
  static final PassiveArtFetcherService instance =
      PassiveArtFetcherService._internal();

  PassiveArtFetcherService._internal();

  factory PassiveArtFetcherService() => instance;

  static const String _attemptedArtistsKey = 'art_fetch_attempted_artists';
  static const String _attemptedAlbumsKey = 'art_fetch_attempted_albums';
  static const String _libraryScanDateKey = 'art_fetch_library_scan_date';

  dynamic _containerRef;
  bool _isForegrounded = true;
  bool _isRunning = false;

  /// In-memory: do not re-attempt these this process, whatever the reason.
  final Set<String> _attemptedArtists = {};
  final Set<String> _attemptedAlbums = {};

  /// Queued deltas against the persisted lists. Adds come from actual lookup
  /// attempts; removes come from art removal. Independent of the in-memory
  /// sets, so a session-only mark can never leak into storage.
  final Set<String> _persistAddArtists = {};
  final Set<String> _persistRemoveArtists = {};
  final Set<String> _persistAddAlbums = {};
  final Set<String> _persistRemoveAlbums = {};

  final List<String> _priorityArtistQueue = [];
  final List<Map<String, String>> _priorityAlbumQueue = [];

  Timer? _persistTimer;
  Future<void>? _flushInFlight;

  void init(dynamic ref) {
    _containerRef = ref;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initAttemptedThenStart());
  }

  Future<void> _initAttemptedThenStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _attemptedArtists
        ..clear()
        ..addAll(prefs.getStringList(_attemptedArtistsKey) ?? const []);
      _attemptedAlbums
        ..clear()
        ..addAll(prefs.getStringList(_attemptedAlbumsKey) ?? const []);
    } catch (_) {
      // A failed load just means everything is re-attempted this session.
    }
    start();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isRunning = false;
    unawaited(_flushPersist());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForegrounded = (state == AppLifecycleState.resumed);
    if (_isForegrounded) {
      start();
    } else {
      unawaited(_flushPersist());
    }
  }

  /// Session-only: remembers [artist] so nothing re-searches it this process.
  void markArtistAttempted(String artist) {
    _attemptedArtists.add(artist.toLowerCase());
  }

  /// Session-only: remembers this album so nothing re-searches it this process.
  void markAlbumAttempted(String album, String? artist) {
    final compositeKey = artist != null && artist.isNotEmpty
        ? '${artist.toLowerCase()}|${album.toLowerCase()}'
        : album.toLowerCase();
    _attemptedAlbums.add(compositeKey);
  }

  /// Lifts a persisted miss for [artist] so a future session can try again.
  /// Called when the user removes art, which otherwise would stay suppressed
  /// forever by a recorded miss. The in-memory suppression is restored by the
  /// caller's `markArtistAttempted` afterwards.
  void forgetArtistAttempt(String artist) {
    final lower = artist.toLowerCase();
    _attemptedArtists.remove(lower);
    _persistAddArtists.remove(lower);
    _persistRemoveArtists.add(lower);
    _schedulePersist();
  }

  /// Lifts a persisted miss for this album, mirroring [forgetArtistAttempt].
  void forgetAlbumAttempt(String album, String? artist) {
    final compositeKey = artist != null && artist.isNotEmpty
        ? '${artist.toLowerCase()}|${album.toLowerCase()}'
        : album.toLowerCase();
    _attemptedAlbums.remove(compositeKey);
    _persistAddAlbums.remove(compositeKey);
    _persistRemoveAlbums.add(compositeKey);
    _schedulePersist();
  }

  /// Drops every recorded attempt so the next session treats the whole
  /// library as unfetched again. Called when the user wipes all art.
  Future<void> clearAttempted() async {
    _attemptedArtists.clear();
    _attemptedAlbums.clear();
    _persistAddArtists.clear();
    _persistRemoveArtists.clear();
    _persistAddAlbums.clear();
    _persistRemoveAlbums.clear();
    _persistTimer?.cancel();
    _persistTimer = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_attemptedArtistsKey);
      await prefs.remove(_attemptedAlbumsKey);
    } catch (_) {}
  }

  void fetchArtistArtIfNeeded(String artist) {
    final clean = OnlineMetadataService.cleanTag(artist);
    if (clean == null) return;
    final lower = clean.toLowerCase();
    if (_attemptedArtists.contains(lower)) return;

    final ref = _containerRef;
    if (ref != null) {
      final artState = ref.read(artistAlbumArtProvider);
      if (artState.getArtistArt(clean) != null) {
        _attemptedArtists.add(lower);
        return;
      }
    }

    if (!_priorityArtistQueue.contains(clean)) {
      _priorityArtistQueue.insert(0, clean);
    }
    start();
  }

  void fetchAlbumArtIfNeeded(String album, String? artist) {
    final cleanAlbum = OnlineMetadataService.cleanTag(album);
    if (cleanAlbum == null) return;
    final cleanArtist = OnlineMetadataService.cleanTag(artist);
    final compositeKey = cleanArtist != null
        ? '${cleanArtist.toLowerCase()}|${cleanAlbum.toLowerCase()}'
        : cleanAlbum.toLowerCase();

    if (_attemptedAlbums.contains(compositeKey)) return;

    final ref = _containerRef;
    if (ref != null) {
      final artState = ref.read(artistAlbumArtProvider);
      if (artState.getAlbumArt(cleanAlbum, artistName: cleanArtist) != null) {
        _attemptedAlbums.add(compositeKey);
        return;
      }
    }

    final item = {'album': cleanAlbum, 'artist': cleanArtist ?? ''};
    if (!_priorityAlbumQueue.any((m) =>
        m['album'] == cleanAlbum && m['artist'] == (cleanArtist ?? ''))) {
      _priorityAlbumQueue.insert(0, item);
    }
    start();
  }

  void start() {
    if (_isRunning || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _isRunning = true;
    unawaited(_runPassiveLoop());
  }

  /// Queues a debounced flush of the pending persist deltas, so a long sweep
  /// does not hammer SharedPreferences once per item.
  void _schedulePersist() {
    if (_persistTimer != null) return;
    _persistTimer = Timer(const Duration(seconds: 3), () {
      _persistTimer = null;
      unawaited(_flushPersist());
    });
  }

  Future<void> _flushPersist() {
    // Coalesce concurrent flushes (timer + lifecycle) into one write pass.
    final inFlight = _flushInFlight ??=
        _doFlushPersist().whenComplete(() => _flushInFlight = null);
    return inFlight;
  }

  Future<void> _doFlushPersist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Snapshot the deltas up front, then remove exactly those afterwards,
      // so an attempt recorded while the write is in flight is not dropped.
      final artistAdds = Set<String>.from(_persistAddArtists);
      final artistRemoves = Set<String>.from(_persistRemoveArtists);
      final albumAdds = Set<String>.from(_persistAddAlbums);
      final albumRemoves = Set<String>.from(_persistRemoveAlbums);
      await _applyDelta(prefs, _attemptedArtistsKey, artistAdds, artistRemoves);
      await _applyDelta(prefs, _attemptedAlbumsKey, albumAdds, albumRemoves);
      _persistAddArtists.removeAll(artistAdds);
      _persistRemoveArtists.removeAll(artistRemoves);
      _persistAddAlbums.removeAll(albumAdds);
      _persistRemoveAlbums.removeAll(albumRemoves);
    } catch (_) {}
  }

  Future<void> _applyDelta(SharedPreferences prefs, String key,
      Set<String> adds, Set<String> removes) async {
    if (adds.isEmpty && removes.isEmpty) return;
    final current = (prefs.getStringList(key) ?? const []).toSet()
      ..removeAll(removes)
      ..addAll(adds);
    await prefs.setStringList(key, current.toList());
  }

  Future<void> _runPassiveLoop() async {
    while (_isRunning && _isForegrounded) {
      try {
        final ref = _containerRef;
        if (ref == null) break;

        // 1. Process priority artist requests first (user-initiated)
        while (
            _priorityArtistQueue.isNotEmpty && _isRunning && _isForegrounded) {
          final artist = _priorityArtistQueue.removeAt(0);
          final lower = artist.toLowerCase();
          if (_attemptedArtists.contains(lower)) continue;
          _attemptedArtists.add(lower);
          _persistAddArtists.add(lower);
          _schedulePersist();

          await _fetchArtistArt(artist);
          await Future.delayed(const Duration(milliseconds: 350));
        }

        // 2. Process priority album requests (user-initiated)
        while (
            _priorityAlbumQueue.isNotEmpty && _isRunning && _isForegrounded) {
          final item = _priorityAlbumQueue.removeAt(0);
          final album = item['album']!;
          final artist = item['artist']!;
          final compositeKey = artist.isNotEmpty
              ? '${artist.toLowerCase()}|${album.toLowerCase()}'
              : album.toLowerCase();

          if (_attemptedAlbums.contains(compositeKey)) continue;
          _attemptedAlbums.add(compositeKey);
          _persistAddAlbums.add(compositeKey);
          _schedulePersist();

          await _fetchAlbumArt(album, artist);
          await Future.delayed(const Duration(milliseconds: 500));
        }

        // 3+4. Library-wide sweep for missing art, at most once per day.
        if (_isRunning &&
            _isForegrounded &&
            _priorityArtistQueue.isEmpty &&
            _priorityAlbumQueue.isEmpty &&
            await _shouldRunLibraryScan()) {
          await _scanLibraryArt();
        }
      } catch (e) {
        debugPrint('PassiveArtFetcherService error: $e');
      }

      await Future.delayed(const Duration(seconds: 15));
    }
    _isRunning = false;
  }

  Future<bool> _shouldRunLibraryScan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_libraryScanDateKey) != _dateKey(DateTime.now());
    } catch (_) {
      return true;
    }
  }

  Future<void> _scanLibraryArt() async {
    final ref = _containerRef;
    if (ref == null) return;
    final songs = ref.read(songsProvider).value ?? const <Song>[];

    if (songs.isNotEmpty) {
      final artists = songs
          .map((s) => OnlineMetadataService.cleanTag(s.artist))
          .whereType<String>()
          .toSet();

      final missingArtists = artists
          .where((a) =>
              !_attemptedArtists.contains(a.toLowerCase()) &&
              ref.read(artistAlbumArtProvider).getArtistArt(a) == null)
          .toList();

      for (final artist in missingArtists) {
        if (!_isRunning ||
            !_isForegrounded ||
            _priorityArtistQueue.isNotEmpty ||
            _priorityAlbumQueue.isNotEmpty) {
          break;
        }
        _attemptedArtists.add(artist.toLowerCase());
        _persistAddArtists.add(artist.toLowerCase());
        _schedulePersist();

        await _fetchArtistArt(artist);
        await Future.delayed(const Duration(seconds: 2));
      }

      if (_isRunning &&
          _isForegrounded &&
          _priorityArtistQueue.isEmpty &&
          _priorityAlbumQueue.isEmpty) {
        final albums = <Map<String, String>>[];
        final seenKeys = <String>{};

        for (final song in songs) {
          final album = OnlineMetadataService.cleanTag(song.album);
          if (album == null) continue;
          final artist = OnlineMetadataService.cleanTag(song.artist);
          final key = artist != null
              ? '${artist.toLowerCase()}|${album.toLowerCase()}'
              : album.toLowerCase();

          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            albums.add({'album': album, 'artist': artist ?? ''});
          }
        }

        final missingAlbums = albums.where((item) {
          final album = item['album']!;
          final artist = item['artist']!;
          final key = artist.isNotEmpty
              ? '${artist.toLowerCase()}|${album.toLowerCase()}'
              : album.toLowerCase();
          return !_attemptedAlbums.contains(key) &&
              ref
                      .read(artistAlbumArtProvider)
                      .getAlbumArt(album, artistName: artist) ==
                  null;
        }).toList();

        for (final item in missingAlbums) {
          if (!_isRunning ||
              !_isForegrounded ||
              _priorityArtistQueue.isNotEmpty ||
              _priorityAlbumQueue.isNotEmpty) {
            break;
          }

          final album = item['album']!;
          final artist = item['artist']!;
          final compositeKey = artist.isNotEmpty
              ? '${artist.toLowerCase()}|${album.toLowerCase()}'
              : album.toLowerCase();
          _attemptedAlbums.add(compositeKey);
          _persistAddAlbums.add(compositeKey);
          _schedulePersist();

          await _fetchAlbumArt(album, artist);
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    // Mark the day done even when the sweep was cut short by backgrounding;
    // whatever is left is retried on the next foreground day. An empty library
    // must not consume the daily budget — the sweep should wait for real songs.
    if (songs.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_libraryScanDateKey, _dateKey(DateTime.now()));
    } catch (_) {}
  }

  /// Looks up and saves artist art for [artist] (recording the attempt first).
  /// Returns true when art is present afterwards, false when every source
  /// came up empty.
  Future<bool> _fetchArtistArt(String artist) async {
    final ref = _containerRef;
    if (ref == null) return false;
    final notifier = ref.read(artistAlbumArtProvider.notifier);
    final onlineService = OnlineMetadataService.instance;

    if (ref.read(artistAlbumArtProvider).getArtistArt(artist) != null) {
      return true;
    }

    // Cheap JSON APIs first; the Last.fm scrape downloads whole HTML pages,
    // so it is the last resort.
    var imageUrl = await onlineService.searchITunesArtistImage(artist);
    var source = 'itunes';

    if (imageUrl == null || imageUrl.isEmpty) {
      imageUrl = await onlineService.searchDeezerArtistImage(artist);
      source = 'deezer';
    }

    if (imageUrl == null || imageUrl.isEmpty) {
      imageUrl = await onlineService.searchLastfmArtistImage(artist);
      source = 'lastfm';
    }

    if (imageUrl == null || imageUrl.isEmpty) return false;

    if (ref.read(artistAlbumArtProvider).getArtistArt(artist) != null) {
      return true;
    }

    final localPath = await onlineService.downloadAndCacheCover(
      imageUrl,
      'artist_$artist',
    );
    if (localPath == null || localPath.isEmpty) return false;

    if (ref.read(artistAlbumArtProvider).getArtistArt(artist) == null) {
      await notifier.setArtistArt(
        artistName: artist,
        localPath: localPath,
        imageUrl: imageUrl,
        source: source,
      );
    }
    return true;
  }

  /// Looks up and saves album art for [album] by [artist] (recording the
  /// attempt first). Returns true when art is present afterwards.
  Future<bool> _fetchAlbumArt(String album, String artist) async {
    final ref = _containerRef;
    if (ref == null) return false;
    final notifier = ref.read(artistAlbumArtProvider.notifier);
    final onlineService = OnlineMetadataService.instance;

    if (ref.read(artistAlbumArtProvider).getAlbumArt(album,
            artistName: artist.isNotEmpty ? artist : null) !=
        null) {
      return true;
    }

    final saveKey = artist.isNotEmpty ? '$artist|$album' : album;

    var imageUrl = await onlineService.searchITunesAlbumImage(album,
        artistName: artist.isNotEmpty ? artist : null);
    var source = 'itunes';

    if (imageUrl == null || imageUrl.isEmpty) {
      imageUrl = await onlineService.searchDeezerAlbumImage(album,
          artistName: artist.isNotEmpty ? artist : null);
      source = 'deezer';
    }

    if (imageUrl == null || imageUrl.isEmpty) {
      imageUrl = await onlineService.searchLastfmAlbumImage(album,
          artistName: artist.isNotEmpty ? artist : null);
      source = 'lastfm';
    }

    if (imageUrl == null || imageUrl.isEmpty) return false;

    if (ref.read(artistAlbumArtProvider).getAlbumArt(album,
            artistName: artist.isNotEmpty ? artist : null) !=
        null) {
      return true;
    }

    final localPath = await onlineService.downloadAndCacheCover(
      imageUrl,
      'album_$saveKey',
    );
    if (localPath == null || localPath.isEmpty) return false;

    if (ref.read(artistAlbumArtProvider).getAlbumArt(album,
            artistName: artist.isNotEmpty ? artist : null) ==
        null) {
      await notifier.setAlbumArt(
        albumKey: saveKey,
        albumName: album,
        artistName: artist.isNotEmpty ? artist : null,
        localPath: localPath,
        imageUrl: imageUrl,
        source: source,
      );
    }
    return true;
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
