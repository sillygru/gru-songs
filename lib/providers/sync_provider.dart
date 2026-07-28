import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';

class SyncState {
  final bool isAuthenticated;
  final String? accountEmail;
  final bool isSyncing;
  final String? syncStatusMessage;
  final double? syncProgress;
  final double? lastSyncedAt;
  final String? lastError;
  final int localPlayCount;
  final int remotePlayCount;
  final int totalPlayCount;

  const SyncState({
    this.isAuthenticated = false,
    this.accountEmail,
    this.isSyncing = false,
    this.syncStatusMessage,
    this.syncProgress,
    this.lastSyncedAt,
    this.lastError,
    this.localPlayCount = 0,
    this.remotePlayCount = 0,
    this.totalPlayCount = 0,
  });

  SyncState copyWith({
    bool? isAuthenticated,
    String? accountEmail,
    bool? isSyncing,
    String? syncStatusMessage,
    double? syncProgress,
    double? lastSyncedAt,
    String? lastError,
    int? localPlayCount,
    int? remotePlayCount,
    int? totalPlayCount,
  }) {
    return SyncState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      accountEmail: accountEmail ?? this.accountEmail,
      isSyncing: isSyncing ?? this.isSyncing,
      syncStatusMessage: syncStatusMessage ?? this.syncStatusMessage,
      syncProgress: syncProgress ?? this.syncProgress,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: lastError ?? this.lastError,
      localPlayCount: localPlayCount ?? this.localPlayCount,
      remotePlayCount: remotePlayCount ?? this.remotePlayCount,
      totalPlayCount: totalPlayCount ?? this.totalPlayCount,
    );
  }
}

class SyncNotifier extends Notifier<SyncState> {
  @override
  SyncState build() {
    _loadState();
    return const SyncState();
  }

  Future<void> _loadState() async {
    final sync = SyncService.instance;
    final lastSyncedAt = await sync.getLastSyncTimestamp();
    final breakdown = await DatabaseService.instance
        .getPlayStatsDeviceBreakdown(sync.deviceId);

    state = SyncState(
      isAuthenticated: sync.isSignedIn,
      accountEmail: sync.accountEmail,
      lastSyncedAt: lastSyncedAt,
      localPlayCount: breakdown['localPlayCount'] ?? 0,
      remotePlayCount: breakdown['remotePlayCount'] ?? 0,
      totalPlayCount: breakdown['totalPlayCount'] ?? 0,
    );
  }

  Future<void> refreshDeviceBreakdown() async {
    final sync = SyncService.instance;
    final breakdown = await DatabaseService.instance
        .getPlayStatsDeviceBreakdown(sync.deviceId);
    state = state.copyWith(
      localPlayCount: breakdown['localPlayCount'] ?? 0,
      remotePlayCount: breakdown['remotePlayCount'] ?? 0,
      totalPlayCount: breakdown['totalPlayCount'] ?? 0,
    );
  }

  Future<bool> signIn() async {
    final ok = await SyncService.instance.signIn();
    if (ok) {
      state = state.copyWith(
        isAuthenticated: true,
        accountEmail: SyncService.instance.accountEmail,
        lastError: null,
      );
      await refreshDeviceBreakdown();
    } else {
      final error = SyncService.instance.lastError;
      state = state.copyWith(
        lastError: error != null ? 'Sign-in failed: $error' : 'Sign-in failed',
      );
    }
    return ok;
  }

  Future<void> signOut() async {
    await SyncService.instance.signOut();
    state = const SyncState();
  }

  Future<bool> sync({bool syncSettings = true}) async {
    if (state.isSyncing) return false;
    state = state.copyWith(
      isSyncing: true,
      syncStatusMessage: 'Starting sync...',
      syncProgress: 0.05,
      lastError: null,
    );

    try {
      final ok = await SyncService.instance.sync(
        syncSettings: syncSettings,
        onProgress: (status, progress) {
          state = state.copyWith(
            syncStatusMessage: status,
            syncProgress: progress,
          );
        },
      );

      if (ok) {
        final ts = await SyncService.instance.getLastSyncTimestamp();
        await refreshDeviceBreakdown();
        state = state.copyWith(
          isSyncing: false,
          syncStatusMessage: null,
          syncProgress: null,
          lastSyncedAt: ts,
        );
      } else {
        state = state.copyWith(
          isSyncing: false,
          syncStatusMessage: null,
          syncProgress: null,
          lastError: 'Sync failed',
        );
      }
      return ok;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        syncStatusMessage: null,
        syncProgress: null,
        lastError: e.toString(),
      );
      return false;
    }
  }

  Future<bool> forcePushLocalToCloud({bool syncSettings = true}) async {
    if (state.isSyncing) return false;
    state = state.copyWith(
      isSyncing: true,
      syncStatusMessage: 'Preparing force push...',
      syncProgress: 0.05,
      lastError: null,
    );

    try {
      final ok = await SyncService.instance.forcePushLocalToCloud(
        syncSettings: syncSettings,
        onProgress: (status, progress) {
          state = state.copyWith(
            syncStatusMessage: status,
            syncProgress: progress,
          );
        },
      );

      if (ok) {
        final ts = await SyncService.instance.getLastSyncTimestamp();
        await refreshDeviceBreakdown();
        state = state.copyWith(
          isSyncing: false,
          syncStatusMessage: null,
          syncProgress: null,
          lastSyncedAt: ts,
        );
      } else {
        state = state.copyWith(
          isSyncing: false,
          syncStatusMessage: null,
          syncProgress: null,
          lastError: 'Push failed',
        );
      }
      return ok;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        syncStatusMessage: null,
        syncProgress: null,
        lastError: e.toString(),
      );
      return false;
    }
  }

  Future<bool> forcePullCloudToLocal({bool syncSettings = true}) async {
    if (state.isSyncing) return false;
    state = state.copyWith(
      isSyncing: true,
      syncStatusMessage: 'Preparing force pull...',
      syncProgress: 0.05,
      lastError: null,
    );

    try {
      final ok = await SyncService.instance.forcePullCloudToLocal(
        syncSettings: syncSettings,
        onProgress: (status, progress) {
          state = state.copyWith(
            syncStatusMessage: status,
            syncProgress: progress,
          );
        },
      );

      if (ok) {
        final ts = await SyncService.instance.getLastSyncTimestamp();
        await refreshDeviceBreakdown();
        state = state.copyWith(
          isSyncing: false,
          syncStatusMessage: null,
          syncProgress: null,
          lastSyncedAt: ts,
        );
      } else {
        state = state.copyWith(
          isSyncing: false,
          syncStatusMessage: null,
          syncProgress: null,
          lastError: 'Pull failed',
        );
      }
      return ok;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        syncStatusMessage: null,
        syncProgress: null,
        lastError: e.toString(),
      );
      return false;
    }
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
