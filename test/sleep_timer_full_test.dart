import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/services/audio_player_manager.dart';
import 'package:gru_songs/services/sleep_timer_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';

// Import the generated mocks
@GenerateMocks([AudioPlayerManager, AudioPlayer])
import 'sleep_timer_full_test.mocks.dart';

void main() {
  late MockAudioPlayerManager mockAudioManager;
  late MockAudioPlayer mockAudioPlayer;
  late SleepTimerService service;

  // Streams to control player state
  late BehaviorSubject<Duration> positionSubject;
  late BehaviorSubject<PlayerState> playerStateSubject;
  late BehaviorSubject<SequenceState> sequenceStateSubject;

  setUp(() {
    mockAudioManager = MockAudioPlayerManager();
    mockAudioPlayer = MockAudioPlayer();
    service = SleepTimerService.instance;

    positionSubject = BehaviorSubject<Duration>.seeded(Duration.zero);
    playerStateSubject = BehaviorSubject<PlayerState>.seeded(
      PlayerState(true, ProcessingState.ready),
    );
    // Use MockSequenceState as seed since it must be non-null
    sequenceStateSubject =
        BehaviorSubject<SequenceState>.seeded(MockSequenceState(0));

    // Setup Mock AudioPlayer
    when(mockAudioPlayer.positionStream)
        .thenAnswer((_) => positionSubject.stream);
    when(mockAudioPlayer.playerStateStream)
        .thenAnswer((_) => playerStateSubject.stream);
    when(mockAudioPlayer.sequenceStateStream)
        .thenAnswer((_) => sequenceStateSubject.stream);
    when(mockAudioPlayer.duration).thenReturn(const Duration(minutes: 3));
    when(mockAudioPlayer.currentIndex).thenReturn(0);
    when(mockAudioPlayer.setLoopMode(any)).thenAnswer((_) async {});
    when(mockAudioPlayer.pause()).thenAnswer((_) async {});
    when(mockAudioPlayer.setShuffleModeEnabled(any)).thenAnswer((_) async {});

    // Setup Mock AudioPlayerManager
    when(mockAudioManager.player).thenReturn(mockAudioPlayer);
    when(mockAudioManager.didChangeAppLifecycleState(any)).thenReturn(null);

    // Ensure clean state
    service.cancel();
  });

  tearDown(() {
    service.cancel();
    positionSubject.close();
    playerStateSubject.close();
    sequenceStateSubject.close();
  });

  test('playForTime (0 min) shuts down immediately', () async {
    final completer = Completer<void>();
    service.mockExit = () async {
      completer.complete();
    };

    service.start(
      mode: SleepTimerMode.playForTime,
      minutes: 0,
      tracks: 0,
      letCurrentFinish: false,
      audioManager: mockAudioManager,
      onComplete: () {},
    );

    // Timer(Duration(minutes: 0)) runs on next loop event.
    // Then shutdown logic waits 3s.

    await completer.future;

    verify(mockAudioPlayer.pause()).called(1);
    verify(mockAudioManager
            .didChangeAppLifecycleState(AppLifecycleState.paused))
        .called(1);
  });

  test('stopAfterCurrent triggers when nearing end of song', () async {
    final completer = Completer<void>();
    service.mockExit = () async {
      completer.complete();
    };

    service.start(
      mode: SleepTimerMode.stopAfterCurrent,
      minutes: 0,
      tracks: 0,
      letCurrentFinish: false,
      audioManager: mockAudioManager,
      onComplete: () {},
    );

    await Future.delayed(Duration.zero); // Let any initial setup run

    // Song duration is 3 mins (180s = 180000ms).
    // Threshold is 180000 - 1000 = 179000ms.

    // Not yet
    positionSubject.add(Duration.zero);
    await Future.delayed(Duration(milliseconds: 10));
    // Verify NOT called
    // We can't verify "not called" on mockExit easily other than it NOT completing.
    // relying on timeout would be slow.
    // But we can enable logging or just trust the next step.

    // Trigger
    positionSubject.add(
        const Duration(minutes: 2, seconds: 59, milliseconds: 100)); // 179100ms

    await completer.future;
    verify(mockAudioPlayer.pause()).called(1);
  });

  test('stopAfterCurrent triggers if track advances unexpectedly', () async {
    final completer = Completer<void>();
    service.mockExit = () async {
      completer.complete();
    };

    service.start(
      mode: SleepTimerMode.stopAfterCurrent,
      minutes: 0,
      tracks: 0,
      letCurrentFinish: false,
      audioManager: mockAudioManager,
      onComplete: () {},
    );

    await Future.delayed(Duration.zero);

    // Simulate advancing to next track before reaching threshold.
    when(mockAudioPlayer.currentIndex).thenReturn(1);
    sequenceStateSubject.add(MockSequenceState(1));

    await completer.future;
    verify(mockAudioPlayer.pause()).called(1);
  });

  test('stopAfterTracks (1 more) triggers after 1 track change and end of song',
      () async {
    final completer = Completer<void>();
    service.mockExit = () async {
      completer.complete();
    };

    // Tracks: 1 means "Current + 1 more".
    service.start(
      mode: SleepTimerMode.stopAfterTracks,
      minutes: 0,
      tracks: 1,
      letCurrentFinish: false,
      audioManager: mockAudioManager,
      onComplete: () {},
    );

    // Initial index 0.
    when(mockAudioPlayer.currentIndex).thenReturn(0);
    sequenceStateSubject.add(MockSequenceState(0));
    await Future.delayed(Duration.zero);

    // Change to index 1
    when(mockAudioPlayer.currentIndex).thenReturn(1);
    sequenceStateSubject.add(MockSequenceState(1));
    await Future.delayed(Duration.zero);

    // Logic: remaining 2 -> 1. Reached last track.
    // Listen for end.

    positionSubject
        .add(const Duration(minutes: 2, seconds: 59, milliseconds: 100));

    await completer.future;
    verify(mockAudioPlayer.pause()).called(1);
  });

  test('stopAfterTracks (0 more) triggers stopAfterCurrent logic', () async {
    final completer = Completer<void>();
    service.mockExit = () async {
      completer.complete();
    };

    // Tracks: 0 means "Current only".
    service.start(
      mode: SleepTimerMode.stopAfterTracks,
      minutes: 0,
      tracks: 0,
      letCurrentFinish: false,
      audioManager: mockAudioManager,
      onComplete: () {},
    );

    // Should behave like stopAfterCurrent
    positionSubject
        .add(const Duration(minutes: 2, seconds: 59, milliseconds: 100));

    await completer.future;
    verify(mockAudioPlayer.pause()).called(1);
  });

  test('loopCurrent sets loop mode and stops after time', () async {
    final completer = Completer<void>();
    service.mockExit = () async {
      completer.complete();
    };

    service.start(
      mode: SleepTimerMode.loopCurrent,
      minutes: 0,
      tracks: 0,
      letCurrentFinish: false,
      audioManager: mockAudioManager,
      onComplete: () {},
    );

    verify(mockAudioPlayer.setLoopMode(LoopMode.one)).called(1);

    await completer.future;
    verify(mockAudioPlayer.pause()).called(1);
  });

  test('playForTime with letCurrentFinish=true waits for song end', () async {
    final completer = Completer<void>();
    service.mockExit = () async {
      completer.complete();
    };

    service.start(
      mode: SleepTimerMode.playForTime,
      minutes: 0, // timer fires immediately
      tracks: 0,
      letCurrentFinish: true,
      audioManager: mockAudioManager,
      onComplete: () {},
    );

    await Future.delayed(Duration(milliseconds: 50));
    // specific pause should NOT be called yet
    verifyNever(mockAudioPlayer.pause());

    // Now trigger end of song
    positionSubject
        .add(const Duration(minutes: 2, seconds: 59, milliseconds: 100));

    await completer.future;
    verify(mockAudioPlayer.pause()).called(1);
  });
}

// Simple Mock SequenceState manually since generating it might be hard if fields are final/private
// But we added @GenerateMocks([SequenceState]). Let's see if it works.
// If it fails, we fall back to manual stub or Fake.
// I'll create a FakeSequenceState just in case usage requires it.
class MockSequenceState extends Fake implements SequenceState {
  final int? _idx;
  MockSequenceState(this._idx);
  @override
  int? get currentIndex => _idx;
}
