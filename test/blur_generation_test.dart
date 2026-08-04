import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wispie/services/ffmpeg_service.dart';

void main() {
  group('generateBlurredImageBytes', () {
    test('blurs and re-encodes a valid image to the requested size', () {
      final source = _solidPng(64, 64, 200, 60, 60);

      final out = generateBlurredImageBytes(
        source,
        width: 32,
        height: 32,
        blurSigma: 5,
      );

      expect(out, isNotNull);
      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 32);
      expect(decoded.height, 32);
    });

    test('returns null for bytes that are not an image', () {
      final out = generateBlurredImageBytes(
        Uint8List.fromList(List.filled(64, 0xAB)),
        width: 32,
        height: 32,
        blurSigma: 5,
      );

      expect(out, isNull);
    });
  });
}

Uint8List _solidPng(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return img.encodePng(image);
}
