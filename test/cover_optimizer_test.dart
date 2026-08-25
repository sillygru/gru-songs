import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wispie/domain/services/cover_optimizer.dart';

void main() {
  group('CoverOptimizer', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cover_optimizer_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('computeContentKey returns deterministic c_<sha1> key', () {
      final bytes1 = Uint8List.fromList([1, 2, 3, 4, 5]);
      final bytes2 = Uint8List.fromList([1, 2, 3, 4, 5]);
      final bytes3 = Uint8List.fromList([5, 4, 3, 2, 1]);

      expect(CoverOptimizer.computeContentKey(bytes1),
          CoverOptimizer.computeContentKey(bytes2));
      expect(CoverOptimizer.computeContentKey(bytes1).startsWith('c_'), isTrue);
      expect(CoverOptimizer.computeContentKey(bytes1),
          isNot(CoverOptimizer.computeContentKey(bytes3)));
    });

    test('saveOptimizedCover deduplicates identical images', () async {
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 0, 0));
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final path1 =
          await CoverOptimizer.saveOptimizedCover(bytes, tempDir.path);
      expect(File(path1).existsSync(), isTrue);

      final filesBefore = tempDir.listSync().length;

      // Second save with the identical bytes should immediately return existing path
      final path2 =
          await CoverOptimizer.saveOptimizedCover(bytes, tempDir.path);
      final filesAfter = tempDir.listSync().length;

      expect(path1, path2);
      expect(filesBefore, filesAfter);
    });

    test('saveOptimizedCover resizes oversized images down to maxDimension',
        () async {
      // Create a 1600x1200 image (larger than default 1024)
      final largeImage = img.Image(width: 1600, height: 1200);
      img.fill(largeImage, color: img.ColorRgb8(0, 128, 255));
      final largeBytes = Uint8List.fromList(img.encodeJpg(largeImage));

      final savedPath = await CoverOptimizer.saveOptimizedCover(
        largeBytes,
        tempDir.path,
        maxDimension: 1024,
      );

      final savedFile = File(savedPath);
      expect(savedFile.existsSync(), isTrue);

      final decoded = img.decodeImage(await savedFile.readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, 1024);
      expect(decoded.height, 768); // 1200 * 1024 / 1600 = 768
    });

    test('saveOptimizedCover handles tall images preserving aspect ratio',
        () async {
      // Create a 1200x1800 tall image
      final tallImage = img.Image(width: 1200, height: 1800);
      img.fill(tallImage, color: img.ColorRgb8(50, 200, 50));
      final tallBytes = Uint8List.fromList(img.encodeJpg(tallImage));

      final savedPath = await CoverOptimizer.saveOptimizedCover(
        tallBytes,
        tempDir.path,
        maxDimension: 1024,
      );

      final savedFile = File(savedPath);
      expect(savedFile.existsSync(), isTrue);

      final decoded = img.decodeImage(await savedFile.readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.height, 1024);
      expect(decoded.width, 683); // 1200 * 1024 / 1800 = 683
    });
  });
}
