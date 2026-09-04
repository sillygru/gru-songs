import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wispie/data/migrations.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh v2 create contains all tables', () async {
    final dir = await Directory.systemTemp.createTemp('migrate_fresh_');
    final path = '${dir.path}/wispie_data.db';
    final db = await openDatabase(path,
        version: kUserDataDbVersion,
        onCreate: (db, v) async => createUserDataSchema(db));
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
    final names = tables.map((r) => r['name'] as String).toSet();
    expect(names.contains('favorite'), isTrue);
    expect(names.contains('queue_snapshot'), isTrue);
    expect(names.contains('translated_lyrics'), isTrue);
    expect(names.contains('artist_art'), isTrue);
    final cols = await db.rawQuery('PRAGMA table_info(translated_lyrics)');
    expect(cols.any((c) => c['name'] == 'source_hash'), isTrue);
    await db.close();
    await dir.delete(recursive: true);
  });

  test('upgrade v1->v2 adds new tables and source_hash', () async {
    final dir = await Directory.systemTemp.createTemp('migrate_up_');
    final path = '${dir.path}/wispie_data.db';
    final dbV1 = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute(
          'CREATE TABLE favorite (filename TEXT PRIMARY KEY, added_at REAL)');
      await db.execute(
          'CREATE TABLE song (filename TEXT PRIMARY KEY, title TEXT, artist TEXT, album TEXT, url TEXT, cover_url TEXT, has_lyrics INTEGER, play_count INTEGER, duration_ms INTEGER, mtime REAL, created_epoch_sec REAL, song_date_epoch_sec REAL)');
      await db.execute(
          'CREATE TABLE translated_lyrics (filename TEXT, target_lang TEXT, translated_content TEXT, updated_at REAL, PRIMARY KEY (filename, target_lang))');
    });
    await dbV1.insert('favorite', {'filename': 'a.mp3', 'added_at': 1.0});
    await dbV1.close();

    final dbV2 = await openDatabase(path,
        version: kUserDataDbVersion,
        onCreate: (db, v) async => createUserDataSchema(db),
        onUpgrade: (db, oldV, newV) async {
          if (oldV < 2) await upgradeUserDataFrom1To2(db);
        });
    final fav = await dbV2.query('favorite');
    expect(fav.length, 1);
    final tables = await dbV2.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='queue_snapshot'");
    expect(tables.isNotEmpty, isTrue);
    final cols = await dbV2.rawQuery('PRAGMA table_info(translated_lyrics)');
    expect(cols.any((c) => c['name'] == 'source_hash'), isTrue);
    await dbV2.close();
    await dir.delete(recursive: true);
  });
}
