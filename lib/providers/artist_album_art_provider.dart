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
    if (artistName == null || artistName.isEmpty) return null;
    return artistArt[artistName.toLowerCase()];
  }

  String? getAlbumArt(String? albumName, {String? artistName}) {
    if (albumName == null || albumName.isEmpty) return null;
    if (artistName != null && artistName.isNotEmpty) {
      final compositeKey =
          '${artistName.toLowerCase()}|${albumName.toLowerCase()}';
      final art = albumArt[compositeKey];
      if (art != null) return art;
    }
    return albumArt[albumName.toLowerCase()];
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
      final artists = await db.getArtistArtMap();
      final albums = await db.getAlbumArtMap();
      state = ArtistAlbumArtState(
        artistArt: artists,
        albumArt: albums,
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
    FileImage(File(localPath)).evict();
    await DatabaseService.instance.saveArtistArt(
      artistName: artistName,
      localPath: localPath,
      imageUrl: imageUrl,
      source: source,
    );
    PassiveArtFetcherService.instance.markArtistAttempted(artistName);
    final updated = Map<String, String>.from(state.artistArt);
    updated[artistName.toLowerCase()] = localPath;
    state = state.copyWith(artistArt: updated);
  }

  Future<void> removeArtistArt(String artistName) async {
    final existingPath = state.artistArt[artistName.toLowerCase()];
    if (existingPath != null) {
      FileImage(File(existingPath)).evict();
    }
    await DatabaseService.instance.deleteArtistArt(artistName);
    PassiveArtFetcherService.instance.markArtistAttempted(artistName);
    final updated = Map<String, String>.from(state.artistArt);
    updated.remove(artistName.toLowerCase());
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
    FileImage(File(localPath)).evict();
    await DatabaseService.instance.saveAlbumArt(
      albumKey: albumKey,
      albumName: albumName,
      artistName: artistName,
      localPath: localPath,
      imageUrl: imageUrl,
      source: source,
    );
    PassiveArtFetcherService.instance.markAlbumAttempted(albumName, artistName);
    final updated = Map<String, String>.from(state.albumArt);
    updated[albumKey.toLowerCase()] = localPath;
    state = state.copyWith(albumArt: updated);
  }

  Future<void> removeAlbumArt(String albumKey) async {
    final existingPath = state.albumArt[albumKey.toLowerCase()];
    if (existingPath != null) {
      FileImage(File(existingPath)).evict();
    }
    await DatabaseService.instance.deleteAlbumArt(albumKey);
    final parts = albumKey.split('|');
    if (parts.length == 2) {
      PassiveArtFetcherService.instance.markAlbumAttempted(parts[1], parts[0]);
    } else {
      PassiveArtFetcherService.instance.markAlbumAttempted(albumKey, null);
    }
    final updated = Map<String, String>.from(state.albumArt);
    updated.remove(albumKey.toLowerCase());
    state = state.copyWith(albumArt: updated);
  }

  Future<void> clearAll() async {
    await DatabaseService.instance.clearArtistArt();
    await DatabaseService.instance.clearAlbumArt();
    state = const ArtistAlbumArtState(isLoaded: true);
  }
}

final artistAlbumArtProvider =
    NotifierProvider<ArtistAlbumArtNotifier, ArtistAlbumArtState>(
  ArtistAlbumArtNotifier.new,
);
