import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wispie/services/file_manager_service.dart';

/// The whole reason metadata can now be edited while a song plays is that the
/// write never touches the bytes the player is already reading. These tests pin
/// that property, because losing it silently corrupts playback rather than
/// throwing anything.
void main() {
  late Directory tempDir;
  late FileManagerService fileManager;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wispie_atomic_');
    fileManager = FileManagerService();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeFile(String name, String content) {
    final file = File(p.join(tempDir.path, name));
    file.writeAsStringSync(content);
    return file;
  }

  test('the target ends up with the source content', () async {
    final target = writeFile('song.mp3', 'old bytes');
    final source = writeFile('staged.mp3', 'new bytes');

    await fileManager.replaceFileAtomically(
      source: source,
      targetPath: target.path,
    );

    expect(target.readAsStringSync(), 'new bytes');
  });

  test('a reader that already had the file open keeps seeing the old bytes',
      () async {
    final target = writeFile('song.mp3', 'old bytes');
    final source = writeFile('staged.mp3', 'new bytes');

    // Stands in for just_audio holding the track open mid-playback.
    final openHandle = target.openSync();
    addTearDown(openHandle.closeSync);

    await fileManager.replaceFileAtomically(
      source: source,
      targetPath: target.path,
    );

    // Replacing the directory entry leaves the original inode alive for
    // whoever still holds it. If this ever reads 'new bytes', the write went
    // through the target in place and playback would glitch or die.
    final seenByPlayer = String.fromCharCodes(
      openHandle.readSync('old bytes'.length),
    );
    expect(seenByPlayer, 'old bytes');

    // Meanwhile anything opening it fresh gets the new content.
    expect(File(target.path).readAsStringSync(), 'new bytes');
  });

  test('leaves no staging file behind', () async {
    final target = writeFile('song.mp3', 'old');
    final source = writeFile('staged.mp3', 'new');

    await fileManager.replaceFileAtomically(
      source: source,
      targetPath: target.path,
    );

    expect(File('${target.path}.wispie_tmp').existsSync(), isFalse);
  });

  test('reuses a staging path left over from an interrupted write', () async {
    final target = writeFile('song.mp3', 'old');
    final source = writeFile('staged.mp3', 'new');
    // Debris from a previous run that died between copy and rename.
    writeFile('song.mp3.wispie_tmp', 'stale garbage');

    await fileManager.replaceFileAtomically(
      source: source,
      targetPath: target.path,
    );

    expect(target.readAsStringSync(), 'new');
    expect(File('${target.path}.wispie_tmp').existsSync(), isFalse);
  });

  test('a failed write leaves the original intact and cleans up', () async {
    final target = writeFile('song.mp3', 'original');
    final missing = File(p.join(tempDir.path, 'does_not_exist.mp3'));

    await expectLater(
      fileManager.replaceFileAtomically(
        source: missing,
        targetPath: target.path,
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(target.readAsStringSync(), 'original');
    expect(File('${target.path}.wispie_tmp').existsSync(), isFalse);
  });

  test('creates the target when there is nothing there yet', () async {
    final source = writeFile('staged.mp3', 'fresh');
    final targetPath = p.join(tempDir.path, 'new_song.mp3');

    await fileManager.replaceFileAtomically(
      source: source,
      targetPath: targetPath,
    );

    expect(File(targetPath).readAsStringSync(), 'fresh');
  });
}
