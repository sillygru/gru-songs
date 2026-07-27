import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sync_service.dart';

class SyncState {
  final bool isAuthenticated;
  final String? accountEmail;
  final bool isSyncing;
  final double? lastSyncedAt;
  final String? lastError;

  const SyncState({
    this.isAuthenticated = false,
    this.accountEmail,
    this.isSyncing = false,
    this.lastSyncedAt,
    this.lastError,
  });

  SyncState copyWith({
    bool? isAuthenticated,
    String? accountEmail,
    bool? isSyncing,
    double? lastSyncedAt,
    String? lastError,
  }) {
    return SyncState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      accountEmail: accountEmail ?? this.accountEmail,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: lastError ?? this.lastError,
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
    state = SyncState(
      isAuthenticated: sync.isSignedIn,
      accountEmail: sync.accountEmail,
      lastSyncedAt: lastSyncedAt,
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

  Future<bool> sync() async {
    if (state.isSyncing) return false;
    state = state.copyWith(isSyncing: true, lastError: null);
    try {
      final ok = await SyncService.instance.sync();
      if (ok) {
        final ts = await SyncService.instance.getLastSyncTimestamp();
        state = state.copyWith(isSyncing: false, lastSyncedAt: ts);
      } else {
        state = state.copyWith(isSyncing: false, lastError: 'Sync failed');
      }
      return ok;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
      return false;
    }
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
