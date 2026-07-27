import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/song.dart';
import '../providers/artist_album_art_provider.dart';
import '../providers/providers.dart';
import 'online_metadata_service.dart';

/// Passively fetches missing artist and album artwork while the app is foregrounded.
class PassiveArtFetcherService with WidgetsBindingObserver {
  static final PassiveArtFetcherService instance =
      PassiveArtFetcherService._internal();

  PassiveArtFetcherService._internal();

  factory PassiveArtFetcherService() => instance;

  dynamic _containerRef;
  bool _isForegrounded = true;
  bool _isRunning = false;

  final Set<String> _attemptedArtists = {};
  final Set<String> _attemptedAlbums = {};
  final List<String> _priorityArtistQueue = [];
  final List<Map<String, String>> _priorityAlbumQueue = [];

  void init(dynamic ref) {
    _containerRef = ref;
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isRunning = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForegrounded = (state == AppLifecycleState.resumed);
    if (_isForegrounded) {
      start();
    }
  }

  void markArtistAttempted(String artist) {
    _attemptedArtists.add(artist.toLowerCase());
  }

  void markAlbumAttempted(String album, String? artist) {
    final compositeKey = artist != null && artist.isNotEmpty
        ? '${artist.toLowerCase()}|${album.toLowerCase()}'
        : album.toLowerCase();
    _attemptedAlbums.add(compositeKey);
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

  Future<void> _runPassiveLoop() async {
    while (_isRunning && _isForegrounded) {
      try {
        final ref = _containerRef;
        if (ref == null) break;

        final notifier = ref.read(artistAlbumArtProvider.notifier);
        final onlineService = OnlineMetadataService.instance;

        // 1. Process priority artist requests first
        while (
            _priorityArtistQueue.isNotEmpty && _isRunning && _isForegrounded) {
          final artist = _priorityArtistQueue.removeAt(0);
          final lower = artist.toLowerCase();
          if (_attemptedArtists.contains(lower)) continue;
          _attemptedArtists.add(lower);

          if (ref.read(artistAlbumArtProvider).getArtistArt(artist) != null) {
            continue;
          }

          var imageUrl = await onlineService.searchLastfmArtistImage(artist);
          var source = 'lastfm';

          if (imageUrl == null || imageUrl.isEmpty) {
            imageUrl = await onlineService.searchITunesArtistImage(artist);
            source = 'itunes';
          }

          if (imageUrl == null || imageUrl.isEmpty) {
            imageUrl = await onlineService.searchDeezerArtistImage(artist);
            source = 'deezer';
          }

          if (imageUrl != null && imageUrl.isNotEmpty) {
            if (ref.read(artistAlbumArtProvider).getArtistArt(artist) != null) {
              continue;
            }

            final localPath = await onlineService.downloadAndCacheCover(
              imageUrl,
              'artist_$artist',
            );
            if (localPath != null && localPath.isNotEmpty) {
              if (ref.read(artistAlbumArtProvider).getArtistArt(artist) ==
                  null) {
                await notifier.setArtistArt(
                  artistName: artist,
                  localPath: localPath,
                  imageUrl: imageUrl,
                  source: source,
                );
              }
            }
          }
          await Future.delayed(const Duration(milliseconds: 350));
        }

        // 2. Process priority album requests
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

          if (ref
                  .read(artistAlbumArtProvider)
                  .getAlbumArt(album, artistName: artist) !=
              null) {
            continue;
          }

          final saveKey = artist.isNotEmpty ? '$artist|$album' : album;
          var imageUrl = await onlineService.searchLastfmAlbumImage(album,
              artistName: artist);
          var source = 'lastfm';

          if (imageUrl == null || imageUrl.isEmpty) {
            imageUrl = await onlineService.searchITunesAlbumImage(album,
                artistName: artist);
            source = 'itunes';
          }

          if (imageUrl == null || imageUrl.isEmpty) {
            imageUrl = await onlineService.searchDeezerAlbumImage(album,
                artistName: artist);
            source = 'deezer';
          }

          if (imageUrl != null && imageUrl.isNotEmpty) {
            if (ref
                    .read(artistAlbumArtProvider)
                    .getAlbumArt(album, artistName: artist) !=
                null) {
              continue;
            }

            final localPath = await onlineService.downloadAndCacheCover(
              imageUrl,
              'album_$saveKey',
            );
            if (localPath != null && localPath.isNotEmpty) {
              if (ref
                      .read(artistAlbumArtProvider)
                      .getAlbumArt(album, artistName: artist) ==
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
            }
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }

        // 3. Scan missing artists in library
        final songs = ref.read(songsProvider).value ?? const <Song>[];
        if (songs.isNotEmpty && _isRunning && _isForegrounded) {
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
                _priorityArtistQueue.isNotEmpty) {
              break;
            }
            _attemptedArtists.add(artist.toLowerCase());

            if (ref.read(artistAlbumArtProvider).getArtistArt(artist) != null) {
              continue;
            }

            var imageUrl = await onlineService.searchLastfmArtistImage(artist);
            var source = 'lastfm';

            if (imageUrl == null || imageUrl.isEmpty) {
              imageUrl = await onlineService.searchITunesArtistImage(artist);
              source = 'itunes';
            }

            if (imageUrl == null || imageUrl.isEmpty) {
              imageUrl = await onlineService.searchDeezerArtistImage(artist);
              source = 'deezer';
            }

            if (imageUrl != null && imageUrl.isNotEmpty) {
              if (ref.read(artistAlbumArtProvider).getArtistArt(artist) !=
                  null) {
                continue;
              }

              final localPath = await onlineService.downloadAndCacheCover(
                imageUrl,
                'artist_$artist',
              );
              if (localPath != null && localPath.isNotEmpty) {
                if (ref.read(artistAlbumArtProvider).getArtistArt(artist) ==
                    null) {
                  await notifier.setArtistArt(
                    artistName: artist,
                    localPath: localPath,
                    imageUrl: imageUrl,
                    source: source,
                  );
                }
              }
            }

            await Future.delayed(const Duration(seconds: 2));
          }

          // 4. Scan missing albums in library
          if (_isRunning && _isForegrounded && _priorityAlbumQueue.isEmpty) {
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

              if (ref
                      .read(artistAlbumArtProvider)
                      .getAlbumArt(album, artistName: artist) !=
                  null) {
                continue;
              }

              final saveKey = artist.isNotEmpty ? '$artist|$album' : album;

              var imageUrl = await onlineService.searchLastfmAlbumImage(album,
                  artistName: artist);
              var source = 'lastfm';

              if (imageUrl == null || imageUrl.isEmpty) {
                imageUrl = await onlineService.searchITunesAlbumImage(album,
                    artistName: artist);
                source = 'itunes';
              }

              if (imageUrl == null || imageUrl.isEmpty) {
                imageUrl = await onlineService.searchDeezerAlbumImage(album,
                    artistName: artist);
                source = 'deezer';
              }

              if (imageUrl != null && imageUrl.isNotEmpty) {
                if (ref
                        .read(artistAlbumArtProvider)
                        .getAlbumArt(album, artistName: artist) !=
                    null) {
                  continue;
                }

                final localPath = await onlineService.downloadAndCacheCover(
                  imageUrl,
                  'album_$saveKey',
                );
                if (localPath != null && localPath.isNotEmpty) {
                  if (ref
                          .read(artistAlbumArtProvider)
                          .getAlbumArt(album, artistName: artist) ==
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
                }
              }

              await Future.delayed(const Duration(seconds: 2));
            }
          }
        }
      } catch (e) {
        debugPrint('PassiveArtFetcherService error: $e');
      }

      await Future.delayed(const Duration(seconds: 15));
    }
    _isRunning = false;
  }
}
