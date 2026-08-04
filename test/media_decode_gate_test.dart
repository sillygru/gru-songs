import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/media_decode_gate.dart';

void main() {
  group('MediaDecodeGate', () {
    test('runs gated bodies one at a time', () async {
      final order = <String>[];
      final releaseFirst = Completer<void>();

      final first = MediaDecodeGate.run(() async {
        order.add('first:start');
        await releaseFirst.future;
        order.add('first:end');
      });

      // Give the first body time to claim the gate before queuing the second.
      await Future<void>.delayed(Duration.zero);

      final second = MediaDecodeGate.run(() async {
        order.add('second:start');
        order.add('second:end');
      });

      await Future<void>.delayed(Duration.zero);
      expect(order, ['first:start'], reason: 'second must not start yet');

      releaseFirst.complete();
      await Future.wait([first, second]);

      expect(
        order,
        ['first:start', 'first:end', 'second:start', 'second:end'],
      );
    });

    test('a failing body does not break the chain', () async {
      final order = <String>[];

      final failing = MediaDecodeGate.run(() async {
        order.add('first:start');
        throw StateError('boom');
      });

      await expectLater(failing, throwsA(isA<StateError>()));

      final following = MediaDecodeGate.run(() async {
        order.add('second');
      });
      await following;

      expect(order, ['first:start', 'second']);
    });

    test('high priority jumps ahead of queued normal work', () async {
      final order = <String>[];
      final releaseFirst = Completer<void>();

      // Occupies the gate so both later requests stay queued.
      MediaDecodeGate.run(() async {
        order.add('running');
        await releaseFirst.future;
        order.add('running:end');
      });
      await Future<void>.delayed(Duration.zero);

      // Normal work queues first, then a high-priority request arrives.
      final normal = MediaDecodeGate.run(() async {
        order.add('normal');
      });
      await Future<void>.delayed(Duration.zero);

      final high = MediaDecodeGate.run(
        () async {
          order.add('high');
        },
        priority: MediaDecodePriority.high,
      );
      await Future<void>.delayed(Duration.zero);
      expect(order, ['running'], reason: 'gate is still busy');

      releaseFirst.complete();
      await Future.wait([normal, high]);

      expect(
        order,
        ['running', 'running:end', 'high', 'normal'],
        reason: 'the queued high-priority job must run before the normal one',
      );
    });

    test('high priority never preempts a running normal job', () async {
      final order = <String>[];
      final releaseNormal = Completer<void>();

      final normal = MediaDecodeGate.run(() async {
        order.add('normal:start');
        await releaseNormal.future;
        order.add('normal:end');
      });
      await Future<void>.delayed(Duration.zero);

      // Arrives while the normal decode is mid-flight — must still wait for it.
      final high = MediaDecodeGate.run(
        () async => order.add('high'),
        priority: MediaDecodePriority.high,
      );
      await Future<void>.delayed(Duration.zero);
      expect(order, ['normal:start']);

      releaseNormal.complete();
      await Future.wait([normal, high]);

      expect(order, ['normal:start', 'normal:end', 'high']);
    });

    test('high priority stays FIFO among itself', () async {
      final order = <String>[];
      final releaseFirst = Completer<void>();

      MediaDecodeGate.run(() async {
        await releaseFirst.future;
      });
      await Future<void>.delayed(Duration.zero);

      final highA = MediaDecodeGate.run(
        () async => order.add('highA'),
        priority: MediaDecodePriority.high,
      );
      final highB = MediaDecodeGate.run(
        () async => order.add('highB'),
        priority: MediaDecodePriority.high,
      );
      await Future<void>.delayed(Duration.zero);

      releaseFirst.complete();
      await Future.wait([highA, highB]);

      expect(order, ['highA', 'highB']);
    });
  });
}
