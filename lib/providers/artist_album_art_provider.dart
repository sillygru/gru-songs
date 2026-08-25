import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database_service.dart';
import '../services/passive_art_fetcher_service.dart';

class ArtistAlbumArtState {
  final Map<String, String> artistArt; // lowercased artist_name -> localPath
  final Map<String, String> albumArt; // lowercased album_key -> localPath
  final bool isLoaded;

  const ArtistAlbumArtState({
    this.artistArt = const {},
    this.albumArt = const {},
    this.isLoaded = false,
  });

  ArtistAlbumArtState copyWith({
    Map<String, String>? artistArt,
    Map<String, String>? albumArt,
    bool? isLoaded,
  }) {
    return ArtistAlbumArtState(
      artistArt: artistArt ?? this.artistArt,
      albumArt: albumArt ?? this.albumArt,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }

  String? getArtistArt(String? artistName) {
    if (artistName == null) return null;
    final trimmed = artistName.trim();
    if (trimmed.isEmpty) return null;
    return artistArt[trimmed.toLowerCase()];
  }

  String? getAlbumArt(String? albumName, {String? artistName}) {
    if (albumName == null) return null;
    final cleanAlbum = albumName.trim();
    if (cleanAlbum.isEmpty) return null;
    if (artistName != null && artistName.trim().isNotEmpty) {
      final compositeKey =
          '${artistName.trim().toLowerCase()}|${cleanAlbum.toLowerCase()}';
      final art = albumArt[compositeKey];
      if (art != null) return art;
    }
    return albumArt[cleanAlbum.toLowerCase()];
  }
}

class ArtistAlbumArtNotifier extends Notifier<ArtistAlbumArtState> {
  @override
  ArtistAlbumArtState build() {
    _load();
    return const ArtistAlbumArtState();
  }

  Future<void> _load() async {
    try {
      final db = DatabaseService.instance;
      final rawArtists = await db.getArtistArtMap();
      final rawAlbums = await db.getAlbumArtMap();

      final validArtists = <String, String>{};
      final staleArtists = <String>[];
      for (final entry in rawArtists.entries) {
        if (File(entry.value).existsSync()) {
          validArtists[entry.key] = entry.value;
        } else {
          staleArtists.add(entry.key);
        }
      }

      final validAlbums = <String, String>{};
      final staleAlbums = <String>[];
      for (final entry in rawAlbums.entries) {
        if (File(entry.value).existsSync()) {
          validAlbums[entry.key] = entry.value;
        } else {
          staleAlbums.add(entry.key);
        }
      }

      for (final key in staleArtists) {
        unawaited(db.deleteArtistArt(key));
        PassiveArtFetcherService.instance.forgetArtistAttempt(key);
      }
      for (final key in staleAlbums) {
        unawaited(db.deleteAlbumArt(key));
        final parts = key.split('|');
        if (parts.length == 2) {
          PassiveArtFetcherService.instance
              .forgetAlbumAttempt(parts[1], parts[0]);
        } else {
          PassiveArtFetcherService.instance.forgetAlbumAttempt(key, null);
        }
      }

      state = ArtistAlbumArtState(
        artistArt: validArtists,
        albumArt: validAlbums,
        isLoaded: true,
      );
    } catch (_) {}
  }

  Future<void> setArtistArt({
    required String artistName,
    required String localPath,
    String? imageUrl,
    String? source,
  }) async {
    final cleanArtist = artistName.trim();
    FileImage(File(localPath)).evict();
    await DatabaseService.instance.saveArtistArt(
      artistName: cleanArtist,
      localPath: localPath,
      imageUrl: imageUrl,
      source: source,
    );
    PassiveArtFetcherService.instance.markArtistAttempted(cleanArtist);
    final updated = Map<String, String>.from(state.artistArt);
    updated[cleanArtist.toLowerCase()] = localPath;
    state = state.copyWith(artistArt: updated);
  }

  Future<void> removeArtistArt(String artistName) async {
    final cleanArtist = artistName.trim();
    final existingPath = state.artistArt[cleanArtist.toLowerCase()];
    if (existingPath != null) {
      FileImage(File(existingPath)).evict();
    }
    await DatabaseService.instance.deleteArtistArt(cleanArtist);
    // Lift the persisted miss first, so a future session may try again
    // instead of treating a removed art as a permanent miss. The re-mark keeps
    // the in-session suppression, so it is not instantly re-fetched.
    PassiveArtFetcherService.instance.forgetArtistAttempt(cleanArtist);
    PassiveArtFetcherService.instance.markArtistAttempted(cleanArtist);
    final updated = Map<String, String>.from(state.artistArt);
    updated.remove(cleanArtist.toLowerCase());
    state = state.copyWith(artistArt: updated);
  }

  Future<void> setAlbumArt({
    required String albumKey,
    required String albumName,
    String? artistName,
    required String localPath,
    String? imageUrl,
    String? source,
  }) async {
    final cleanKey = albumKey.trim();
    FileImage(File(localPath)).evict();
    await DatabaseService.instance.saveAlbumArt(
      albumKey: cleanKey,
      albumName: albumName.trim(),
      artistName: artistName?.trim(),
      localPath: localPath,
      imageUrl: imageUrl,
      source: source,
    );
    PassiveArtFetcherService.instance.markAlbumAttempted(albumName, artistName);
    final updated = Map<String, String>.from(state.albumArt);
    updated[cleanKey.toLowerCase()] = localPath;
    state = state.copyWith(albumArt: updated);
  }

  Future<void> removeAlbumArt(String albumKey) async {
    final cleanKey = albumKey.trim();
    final existingPath = state.albumArt[cleanKey.toLowerCase()];
    if (existingPath != null) {
      FileImage(File(existingPath)).evict();
    }
    await DatabaseService.instance.deleteAlbumArt(cleanKey);
    final parts = cleanKey.split('|');
    if (parts.length == 2) {
      PassiveArtFetcherService.instance.forgetAlbumAttempt(parts[1], parts[0]);
      PassiveArtFetcherService.instance.markAlbumAttempted(parts[1], parts[0]);
    } else {
      PassiveArtFetcherService.instance.forgetAlbumAttempt(cleanKey, null);
      PassiveArtFetcherService.instance.markAlbumAttempted(cleanKey, null);
    }
    final updated = Map<String, String>.from(state.albumArt);
    updated.remove(cleanKey.toLowerCase());
    state = state.copyWith(albumArt: updated);
  }

  Future<void> clearAll() async {
    await DatabaseService.instance.clearArtistArt();
    await DatabaseService.instance.clearAlbumArt();
    // Art was wiped on purpose: let the fetcher treat the whole library as
    // unfetched again instead of remembering old attempts.
    await PassiveArtFetcherService.instance.clearAttempted();
    state = const ArtistAlbumArtState(isLoaded: true);
  }
}

final artistAlbumArtProvider =
    NotifierProvider<ArtistAlbumArtNotifier, ArtistAlbumArtState>(
  ArtistAlbumArtNotifier.new,
);
