import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/services/ios_folder_access_service.dart';

void main() {
  group('IosFolderSelection.fromMap', () {
    test('accepts bookmarkId', () {
      final selection = IosFolderSelection.fromMap({
        'path': '/music',
        'bookmarkId': 'bookmark-1',
      });

      expect(selection.path, '/music');
      expect(selection.bookmarkId, 'bookmark-1');
    });

    test('falls back to iosBookmarkId', () {
      final selection = IosFolderSelection.fromMap({
        'path': '/music',
        'iosBookmarkId': 'bookmark-2',
      });

      expect(selection.path, '/music');
      expect(selection.bookmarkId, 'bookmark-2');
    });
  });
}
