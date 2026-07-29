import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

@visibleForTesting
String? testWispiePath;

Future<Directory> getWispieDirectory() async {
  if (testWispiePath != null) {
    final dir = Directory(testWispiePath!);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
  final docDir = await getApplicationDocumentsDirectory();
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    return docDir;
  }
  final dir = Directory('${docDir.path}/wispie');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}
