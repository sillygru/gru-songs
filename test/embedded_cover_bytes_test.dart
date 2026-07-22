import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/services/embedded_cover_bytes.dart';

/// A minimal JPEG payload — only the leading bytes matter here.
Uint8List _jpeg() =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);

Uint8List _png() => Uint8List.fromList(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]);

/// The bytes audio_metadata_reader leaves in front of the image when a picture
/// frame's description is UTF-16: everything after the first null byte, which
/// falls inside the description's first character.
Uint8List _withUtf16DescriptionTail(String description, Uint8List image) {
  final tail = <int>[];
  // The parser consumes the BOM and the first character's low byte, so the
  // leftovers start at the first character's high byte.
  for (int i = 1; i < description.length; i++) {
    tail
      ..add(description.codeUnitAt(i) & 0xFF)
      ..add(description.codeUnitAt(i) >> 8);
  }
  tail.addAll([0x00, 0x00]);
  return Uint8List.fromList([...tail, ...image]);
}

void main() {
  group('recoverEmbeddedCover', () {
    test('returns a clean payload untouched', () {
      final cover = recoverEmbeddedCover(_jpeg());

      expect(cover, isNotNull);
      expect(cover!.extension, '.jpg');
      expect(cover.bytes, _jpeg());
    });

    test('strips the tail of a UTF-16 description before a JPEG', () {
      final raw = _withUtf16DescriptionTail('Cover', _jpeg());
      // "over" as UTF-16LE plus the terminator — exactly what the reader
      // hands back for an ffmpeg-tagged file.
      expect(raw.length, _jpeg().length + 10);

      final cover = recoverEmbeddedCover(raw);

      expect(cover, isNotNull);
      expect(cover!.extension, '.jpg');
      expect(cover.bytes, _jpeg());
    });

    test('strips the tail of a UTF-16 description before a PNG', () {
      final cover =
          recoverEmbeddedCover(_withUtf16DescriptionTail('Front', _png()));

      expect(cover, isNotNull);
      expect(cover!.extension, '.png');
      expect(cover.bytes, _png());
    });

    test('reports the sniffed format, not the declared one', () {
      // A frame whose mimetype claims JPEG while the payload is a PNG would
      // otherwise be written to a .jpg file.
      final cover = recoverEmbeddedCover(_png());

      expect(cover!.extension, '.png');
    });

    test('recognises GIF and WebP', () {
      final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      final webp = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00, // size
        0x57, 0x45, 0x42, 0x50, // WEBP
      ]);

      expect(recoverEmbeddedCover(gif)!.extension, '.gif');
      expect(recoverEmbeddedCover(webp)!.extension, '.webp');
    });

    test('accepts BMP only where the payload should start', () {
      final bmp = Uint8List.fromList([0x42, 0x4D, 0x00, 0x00, 0x00, 0x00]);
      expect(recoverEmbeddedCover(bmp)!.extension, '.bmp');

      // The same two bytes deeper in are far too weak a signal to cut on.
      final buried = Uint8List.fromList([0x01, 0x02, 0x42, 0x4D, 0x00, 0x00]);
      expect(recoverEmbeddedCover(buried), isNull);
    });

    test('returns null for junk and for payloads that are too short', () {
      expect(recoverEmbeddedCover(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
      expect(recoverEmbeddedCover(Uint8List(0)), isNull);
      expect(recoverEmbeddedCover(Uint8List.fromList([0xFF, 0xD8])), isNull);
    });

    test('does not cut on a signature buried past the junk window', () {
      final raw = Uint8List.fromList([
        ...List<int>.filled(600, 0x41),
        ..._jpeg(),
      ]);

      expect(recoverEmbeddedCover(raw), isNull);
    });
  });

  group('hasImageSignature', () {
    test('accepts each supported format', () {
      expect(hasImageSignature(_jpeg()), isTrue);
      expect(hasImageSignature(_png()), isTrue);
      expect(
        hasImageSignature(Uint8List.fromList([0x42, 0x4D, 0x00, 0x00])),
        isTrue,
      );
    });

    test('rejects a cover cached with a description tail in front', () {
      final stale = _withUtf16DescriptionTail('Cover', _jpeg());

      expect(
        hasImageSignature(
          Uint8List.sublistView(stale, 0, imageSignatureProbeLength),
        ),
        isFalse,
      );
    });
  });
}
