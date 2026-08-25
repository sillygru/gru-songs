import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/services/queue_ops.dart';
import 'package:wispie/models/queue_item.dart';
import 'package:wispie/models/song.dart';

Song _createSong(String id) {
  return Song(
    title: 'Song $id',
    artist: 'Artist $id',
    album: 'Album $id',
    filename: 'song_$id.mp3',
    url: 'file:///song_$id.mp3',
  );
}

QueueItem _createItem(String id) {
  return QueueItem(
    queueId: id,
    song: _createSong(id),
  );
}

void main() {
  group('queue_ops session top order', () {
    test('updateSessionTopOrder appends when isOverride is false', () {
      final order1 = updateSessionTopOrder([], 'item1', isOverride: false);
      expect(order1, ['item1']);

      final order2 = updateSessionTopOrder(order1, 'item2', isOverride: false);
      expect(order2, ['item1', 'item2']);

      final order3 = updateSessionTopOrder(order2, 'item3', isOverride: false);
      expect(order3, ['item1', 'item2', 'item3']);
    });

    test('updateSessionTopOrder moves to front when isOverride is true', () {
      final initial = ['item1', 'item2', 'item3'];
      final updated = updateSessionTopOrder(initial, 'item3', isOverride: true);
      expect(updated, ['item3', 'item1', 'item2']);

      final updated2 =
          updateSessionTopOrder(updated, 'item2', isOverride: true);
      expect(updated2, ['item2', 'item3', 'item1']);
    });

    test('pruneSessionTopOrder removes played, current, and missing items', () {
      final queue = [
        _createItem('played0'),
        _createItem('current1'),
        _createItem('upcoming2'),
        _createItem('upcoming3'),
      ];

      final topOrder = [
        'played0',
        'current1',
        'upcoming2',
        'upcoming3',
        'missing_id',
      ];

      final pruned = pruneSessionTopOrder(queue, 1, topOrder);
      expect(pruned, ['upcoming2', 'upcoming3']);
    });
  });

  group('planMoveUpcomingToTop', () {
    test('stacks items consecutively after currentIndex in order', () {
      final queue = [
        _createItem('curr'),
        _createItem('song1'),
        _createItem('song2'),
        _createItem('song3'),
        _createItem('song4'),
      ];
      const currentIndex = 0;
      var topOrder = <String>[];

      // Swipe song3 to top
      final plan1 = planMoveUpcomingToTop(
        queue,
        currentIndex,
        'song3',
        sessionTopOrder: topOrder,
      );
      expect(plan1, isNotNull);
      expect(plan1!.from, 3);
      expect(plan1.to, 1);

      var q = applyPlan(queue, plan1);
      topOrder = updateSessionTopOrder(topOrder, 'song3', isOverride: false);
      expect(q.map((i) => i.queueId).toList(),
          ['curr', 'song3', 'song1', 'song2', 'song4']);
      expect(topOrder, ['song3']);

      // Swipe song4 to top -> should stack after song3 (at index 2)
      final plan2 = planMoveUpcomingToTop(
        q,
        currentIndex,
        'song4',
        sessionTopOrder: topOrder,
      );
      expect(plan2, isNotNull);
      expect(plan2!.from, 4);
      expect(plan2.to, 2);

      q = applyPlan(q, plan2);
      topOrder = updateSessionTopOrder(topOrder, 'song4', isOverride: false);
      expect(q.map((i) => i.queueId).toList(),
          ['curr', 'song3', 'song4', 'song1', 'song2']);
      expect(topOrder, ['song3', 'song4']);

      // Swipe song2 to top -> should stack after song4 (at index 3)
      final plan3 = planMoveUpcomingToTop(
        q,
        currentIndex,
        'song2',
        sessionTopOrder: topOrder,
      );
      expect(plan3, isNotNull);
      expect(plan3!.from, 4);
      expect(plan3.to, 3);

      q = applyPlan(q, plan3);
      topOrder = updateSessionTopOrder(topOrder, 'song2', isOverride: false);
      expect(q.map((i) => i.queueId).toList(),
          ['curr', 'song3', 'song4', 'song2', 'song1']);
      expect(topOrder, ['song3', 'song4', 'song2']);
    });

    test(
        'overrides to currentIndex + 1 when swiping an item already in top order',
        () {
      final queue = [
        _createItem('curr'),
        _createItem('song3'),
        _createItem('song4'),
        _createItem('song2'),
        _createItem('song1'),
      ];
      const currentIndex = 0;
      var topOrder = ['song3', 'song4', 'song2'];

      // Swipe song2 (already in topOrder) -> overrides to index 1
      final isOverride = topOrder.contains('song2');
      expect(isOverride, isTrue);

      final plan = planMoveUpcomingToTop(
        queue,
        currentIndex,
        'song2',
        sessionTopOrder: topOrder,
      );
      expect(plan, isNotNull);
      expect(plan!.from, 3);
      expect(plan.to, 1);

      final q = applyPlan(queue, plan);
      topOrder =
          updateSessionTopOrder(topOrder, 'song2', isOverride: isOverride);
      expect(q.map((i) => i.queueId).toList(),
          ['curr', 'song2', 'song3', 'song4', 'song1']);
      expect(topOrder, ['song2', 'song3', 'song4']);
    });

    test('returns null when trying to swipe played or current item', () {
      final queue = [
        _createItem('played'),
        _createItem('curr'),
        _createItem('upcoming'),
      ];
      const currentIndex = 1;

      expect(
        planMoveUpcomingToTop(queue, currentIndex, 'played'),
        isNull,
      );
      expect(
        planMoveUpcomingToTop(queue, currentIndex, 'curr'),
        isNull,
      );
    });
  });

  group('planPlayNext', () {
    test('stacks new items after existing top order', () {
      final queue = [
        _createItem('curr'),
        _createItem('songA'),
        _createItem('songB'),
        _createItem('songRest'),
      ];
      const currentIndex = 0;
      final topOrder = ['songA', 'songB'];

      final candidate = _createItem('newSong');
      final plan = planPlayNext(
        queue,
        currentIndex,
        candidate,
        sessionTopOrder: topOrder,
      );

      expect(plan.isMove, isFalse);
      expect(plan.to, 3);

      final q = applyPlan(queue, plan);
      expect(q.map((i) => i.queueId).toList(),
          ['curr', 'songA', 'songB', 'newSong', 'songRest']);
    });

    test('overrides to currentIndex + 1 when candidate is already in top order',
        () {
      final queue = [
        _createItem('curr'),
        _createItem('songA'),
        _createItem('songB'),
        _createItem('songRest'),
      ];
      const currentIndex = 0;
      final topOrder = ['songA', 'songB'];

      // Play next for songB (already in upcoming queue and topOrder)
      final plan = planPlayNext(
        queue,
        currentIndex,
        _createItem('songB'),
        sessionTopOrder: topOrder,
      );

      expect(plan.isMove, isTrue);
      expect(plan.from, 2);
      expect(plan.to, 1);

      final q = applyPlan(queue, plan);
      expect(q.map((i) => i.queueId).toList(),
          ['curr', 'songB', 'songA', 'songRest']);
    });

    test(
        'preserves played history when playing next a song that already played',
        () {
      final queue = [
        _createItem('playedSong'),
        _createItem('curr'),
        _createItem('songA'),
      ];
      const currentIndex = 1;
      final topOrder = ['songA'];

      // Play next for playedSong
      final plan = planPlayNext(
        queue,
        currentIndex,
        _createItem('playedSong'),
        sessionTopOrder: topOrder,
      );

      // Played song is duplicated into upcoming section rather than moved out of history
      expect(plan.isMove, isFalse);
      expect(plan.to, 3);

      final q = applyPlan(queue, plan);
      expect(q.length, 4);
      expect(q[0].queueId, 'playedSong');
      expect(q[1].queueId, 'curr');
      expect(q[2].queueId, 'songA');
      expect(q[3].song.filename, 'song_playedSong.mp3');
    });

    test('handles advancing playback index smoothly', () {
      final queue = [
        _createItem('oldTrack'),
        _createItem('songA'),
        _createItem('songB'),
        _createItem('other'),
      ];
      // Playback has advanced to songA (index 1)
      const currentIndex = 1;
      final topOrder = ['oldTrack', 'songA', 'songB'];

      final candidate = _createItem('newSong');
      final plan = planPlayNext(
        queue,
        currentIndex,
        candidate,
        sessionTopOrder: topOrder,
      );

      // songB is at index 2 (> currentIndex 1). So target should be index 3 (after songB).
      expect(plan.to, 3);

      final q = applyPlan(queue, plan);
      expect(q.map((i) => i.queueId).toList(),
          ['oldTrack', 'songA', 'songB', 'newSong', 'other']);
    });
  });
}
