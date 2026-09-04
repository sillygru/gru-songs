import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/models/cover_key.dart';
import 'package:wispie/domain/value_objects/filename.dart';

void main() {
  group('Filename', () {
    test('normalized is basename lowercased', () {
      expect(Filename.normalize('/a/B/C/Song.MP3'), 'song.mp3');
      expect(Filename.normalize('Foo.MP3'), 'foo.mp3');
      expect(Filename.fromUrl('/sdcard/Music/foo.mp3'), 'foo.mp3');
    });

    test('same filename different paths equal', () {
      expect(Filename.normalize('/sdcard/Music/foo.mp3'),
          Filename.normalize('/storage/abc/foo.mp3'));
    });

    test('case-insensitive cross-device', () {
      expect(Filename.normalize('Foo.MP3'), Filename.normalize('foo.mp3'));
      final keys = {
        for (final f in ['Foo.MP3', 'bar.mp3']) Filename.normalize(f)
      };
      expect(keys.contains(Filename.normalize('foo.mp3')), isTrue);
      expect(keys.contains(Filename.normalize('BAR.MP3')), isTrue);
      expect(keys.contains(Filename.normalize('baz.mp3')), isFalse);
    });

    test('renaming orphans', () {
      final keys = {
        for (final f in ['foo.mp3']) Filename.normalize(f)
      };
      expect(keys.contains(Filename.normalize('foo2.mp3')), isFalse);
    });
  });

  group('CoverKey hash', () {
    test('hash stable', () {
      expect(const CoverKey('a').hash, const CoverKey('a').hash);
      expect(const CoverKey('a').hash, isNot(equals(const CoverKey('b').hash)));
    });
  });

  group('CoverKey path helpers', () {
    test('normalizes file://', () {
      expect(CoverKey.normalizePath('file:///tmp/a.jpg'), '/tmp/a.jpg');
      expect(CoverKey.normalizePath('/tmp/a.jpg'), '/tmp/a.jpg');
    });
    test('notificationKey sanitizes', () {
      expect(CoverKey.notificationKeyForCoverPath('/a/b c.jpg'),
          isNot(contains(' ')));
      expect(CoverKey.notificationKeyForCoverPath(''), 'cover');
    });
  });
}
