import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/database_service.dart';

import 'test_helpers.dart';

void main() {
  late TestEnvironment testEnv;
  late DatabaseService database;

  setUp(() async {
    testEnv = TestEnvironment();
    testEnv.setUp();
    database = DatabaseService.forTest();
    DatabaseService.instance = database;
    await database.init();
  });

  tearDown(() async {
    await database.close();
    testEnv.tearDown();
  });

  test('queue history hides exact duplicate snapshots', () async {
    const songs = ['a.mp3', 'b.mp3', 'c.mp3'];

    await database.saveQueueSnapshot(
      'snapshot-1',
      'Queue 1',
      1,
      'shuffle',
      songs,
    );
    await database.saveQueueSnapshot(
      'snapshot-2',
      'Queue 2',
      2,
      'shuffle',
      songs,
    );
    await database.saveQueueSnapshot(
      'snapshot-3',
      'Queue 3',
      3,
      'shuffle',
      ['c.mp3', 'b.mp3', 'a.mp3'],
    );

    final history = await database.getQueueHistorySnapshots();

    expect(history.map((snapshot) => snapshot.id), [
      'snapshot-3',
      'snapshot-2',
    ]);
  });
}
