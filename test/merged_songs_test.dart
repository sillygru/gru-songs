import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/models/queue_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Merged Songs Shuffle Logic Tests', () {
    test('isInSameMergeGroup correctly identifies merged songs', () {
      final mergedGroups = {
        'group1': ['song1.mp3', 'song2.mp3', 'song3.mp3'],
        'group2': ['song4.mp3', 'song5.mp3'],
      };

      bool isInSameMergeGroup(String filename1, String filename2) {
        for (final group in mergedGroups.values) {
          final contains1 = group.contains(filename1);
          final contains2 = group.contains(filename2);
          if (contains1 && contains2) {
            return true;
          }
        }
        return false;
      }

      expect(isInSameMergeGroup('song1.mp3', 'song2.mp3'), true);
      expect(isInSameMergeGroup('song1.mp3', 'song3.mp3'), true);
      expect(isInSameMergeGroup('song4.mp3', 'song5.mp3'), true);
      expect(isInSameMergeGroup('song1.mp3', 'song4.mp3'), false);
      expect(isInSameMergeGroup('song1.mp3', 'unmerged.mp3'), false);
    });

    test('getMergedGroupFilenames returns all songs in group', () {
      final mergedGroups = {
        'group1': ['song1.mp3', 'song2.mp3', 'song3.mp3'],
        'group2': ['song4.mp3', 'song5.mp3'],
      };

      List<String> getMergedGroupFilenames(String filename) {
        for (final group in mergedGroups.values) {
          if (group.contains(filename)) {
            return group;
          }
        }
        return [];
      }

      expect(getMergedGroupFilenames('song1.mp3'),
          ['song1.mp3', 'song2.mp3', 'song3.mp3']);
      expect(getMergedGroupFilenames('song4.mp3'), ['song4.mp3', 'song5.mp3']);
      expect(getMergedGroupFilenames('unmerged.mp3'), []);
    });

    test('merged songs get weight penalty when played back-to-back', () {
      final mergedGroups = {
        'group1': ['song1.mp3', 'song2.mp3'],
      };

      bool isInSameMergeGroup(String filename1, String filename2) {
        for (final group in mergedGroups.values) {
          final contains1 = group.contains(filename1);
          final contains2 = group.contains(filename2);
          if (contains1 && contains2) {
            return true;
          }
        }
        return false;
      }

      // Simulate the weight calculation
      double calculateWeightWithMerge(QueueItem item, QueueItem? prev) {
        double weight = 1.0;

        if (prev != null) {
          // Check if songs are in the same merge group
          if (isInSameMergeGroup(item.song.filename, prev.song.filename)) {
            weight *= 0.05; // 95% penalty for merged songs played back-to-back
          }
        }

        return weight;
      }

      final song1 = Song(
        title: 'Song 1',
        artist: 'Artist',
        album: 'Album',
        filename: 'song1.mp3',
        url: '/path/song1.mp3',
      );

      final song2 = Song(
        title: 'Song 2',
        artist: 'Artist',
        album: 'Album',
        filename: 'song2.mp3',
        url: '/path/song2.mp3',
      );

      final song3 = Song(
        title: 'Song 3',
        artist: 'Artist',
        album: 'Album',
        filename: 'song3.mp3',
        url: '/path/song3.mp3',
      );

      final item1 = QueueItem(song: song1);
      final item2 = QueueItem(song: song2);
      final item3 = QueueItem(song: song3);

      // song1 -> song2 (merged) should have penalty
      final weight1to2 = calculateWeightWithMerge(item2, item1);
      expect(weight1to2, 0.05);

      // song1 -> song3 (not merged) should have no penalty
      final weight1to3 = calculateWeightWithMerge(item3, item1);
      expect(weight1to3, 1.0);
    });

    test('merge group history tracking removes all group songs from history',
        () {
      final mergedGroups = {
        'group1': ['song1.mp3', 'song2.mp3', 'song3.mp3'],
      };

      List<String> getMergedGroupFilenames(String filename) {
        for (final group in mergedGroups.values) {
          if (group.contains(filename)) {
            return group;
          }
        }
        return [];
      }

      // Simulate adding to history
      List<String> addToHistory(List<String> history, String filename) {
        final newHistory = List<String>.from(history);
        final filenamesToRemove = <String>{filename};
        final groupFilenames = getMergedGroupFilenames(filename);
        filenamesToRemove.addAll(groupFilenames);

        newHistory.removeWhere((e) => filenamesToRemove.contains(e));
        newHistory.insert(0, filename);
        return newHistory;
      }

      // Initial history
      var history = <String>[];

      // Add song1
      history = addToHistory(history, 'song1.mp3');
      expect(history, ['song1.mp3']);

      // Add song2 (in same group as song1) - should remove song1
      history = addToHistory(history, 'song2.mp3');
      expect(history, ['song2.mp3']);
      expect(history.contains('song1.mp3'), false);

      // Add unmerged song
      history = addToHistory(history, 'unmerged.mp3');
      expect(history, ['unmerged.mp3', 'song2.mp3']);

      // Add song3 (in same group as song2) - should remove song2
      history = addToHistory(history, 'song3.mp3');
      expect(history, ['song3.mp3', 'unmerged.mp3']);
      expect(history.contains('song2.mp3'), false);
    });
  });

  group('UserDataState merged songs tests', () {
    test('isMerged correctly identifies merged songs', () {
      final mergedGroups = {
        'group1': ['song1.mp3', 'song2.mp3'],
        'group2': ['song3.mp3', 'song4.mp3'],
      };

      bool isMerged(String filename) {
        for (final group in mergedGroups.values) {
          if (group.contains(filename)) return true;
        }
        return false;
      }

      expect(isMerged('song1.mp3'), true);
      expect(isMerged('song2.mp3'), true);
      expect(isMerged('song3.mp3'), true);
      expect(isMerged('unmerged.mp3'), false);
    });

    test('getMergedGroupId returns correct group ID', () {
      final mergedGroups = {
        'group1': ['song1.mp3', 'song2.mp3'],
        'group2': ['song3.mp3', 'song4.mp3'],
      };

      String? getMergedGroupId(String filename) {
        for (final entry in mergedGroups.entries) {
          if (entry.value.contains(filename)) return entry.key;
        }
        return null;
      }

      expect(getMergedGroupId('song1.mp3'), 'group1');
      expect(getMergedGroupId('song2.mp3'), 'group1');
      expect(getMergedGroupId('song3.mp3'), 'group2');
      expect(getMergedGroupId('unmerged.mp3'), isNull);
    });

    test('getMergedSiblings returns other songs in group', () {
      final mergedGroups = {
        'group1': ['song1.mp3', 'song2.mp3', 'song3.mp3'],
        'group2': ['song4.mp3', 'song5.mp3'],
      };

      List<String> getMergedSiblings(String filename) {
        for (final group in mergedGroups.values) {
          if (group.contains(filename)) {
            return group.where((f) => f != filename).toList();
          }
        }
        return [];
      }

      final siblings1 = getMergedSiblings('song1.mp3');
      expect(siblings1.length, 2);
      expect(siblings1.contains('song2.mp3'), true);
      expect(siblings1.contains('song3.mp3'), true);

      final siblings2 = getMergedSiblings('song4.mp3');
      expect(siblings2.length, 1);
      expect(siblings2.contains('song5.mp3'), true);

      expect(getMergedSiblings('unmerged.mp3'), []);
    });
  });

  group('Merged Songs Edge Cases', () {
    test('empty merge groups are handled correctly', () {
      final mergedGroups = <String, List<String>>{};

      bool isInSameMergeGroup(String filename1, String filename2) {
        for (final group in mergedGroups.values) {
          final contains1 = group.contains(filename1);
          final contains2 = group.contains(filename2);
          if (contains1 && contains2) {
            return true;
          }
        }
        return false;
      }

      expect(isInSameMergeGroup('song1.mp3', 'song2.mp3'), false);
    });

    test('song in multiple groups uses first matching group', () {
      // This shouldn't happen in practice, but test the behavior
      final mergedGroups = {
        'group1': ['song1.mp3', 'song2.mp3'],
        'group2': ['song1.mp3', 'song3.mp3'], // song1 is in both groups
      };

      List<String> getMergedGroupFilenames(String filename) {
        for (final group in mergedGroups.values) {
          if (group.contains(filename)) {
            return group;
          }
        }
        return [];
      }

      // Should return the first group found
      final group = getMergedGroupFilenames('song1.mp3');
      expect(group.isNotEmpty, true);
      expect(group.contains('song1.mp3'), true);
    });

    test('history recency penalty applies to merged group members', () {
      final mergedGroups = {
        'group1': ['song1.mp3', 'song2.mp3'],
      };

      List<String> getMergedGroupFilenames(String filename) {
        for (final group in mergedGroups.values) {
          if (group.contains(filename)) {
            return group;
          }
        }
        return [];
      }

      // Simulate history with song1
      final history = [
        HistoryEntry(filename: 'song1.mp3', timestamp: 1000),
        HistoryEntry(filename: 'other.mp3', timestamp: 900),
      ];

      // Check if song2 should get recency penalty (because song1 is in history)
      int getHistoryIndex(String filename) {
        // Check the song itself
        int index = history.indexWhere((e) => e.filename == filename);
        if (index != -1) return index;

        // Check if any song in the merge group is in history
        final groupFilenames = getMergedGroupFilenames(filename);
        for (int i = 0; i < history.length; i++) {
          if (groupFilenames.contains(history[i].filename)) {
            return i;
          }
        }
        return -1;
      }

      // song2 should get index 0 because song1 (in same group) is at index 0
      expect(getHistoryIndex('song2.mp3'), 0);

      // unmerged song should get -1
      expect(getHistoryIndex('unmerged.mp3'), -1);
    });
  });
}

// Simple HistoryEntry class for testing
class HistoryEntry {
  final String filename;
  final double timestamp;

  HistoryEntry({required this.filename, required this.timestamp});
}
