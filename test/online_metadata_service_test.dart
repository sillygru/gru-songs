import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/online_metadata_service.dart';

void main() {
  group('OnlineMetadataService', () {
    test('cleanSearchTitle strips official video and lyric video tags', () {
      expect(
        OnlineMetadataService.cleanSearchTitle(
            'Beach Weather - Sex, Drugs, Etc. (Official Video).mp3'),
        'Sex, Drugs, Etc.',
      );
      expect(
        OnlineMetadataService.cleanSearchTitle(
            'BoyWithUke - Gaslight (Official Music Video)'),
        'Gaslight',
      );
      expect(
        OnlineMetadataService.cleanSearchTitle(
            'Stellar - Outta My League (Official Lyric Video)'),
        'Outta My League',
      );
      expect(
        OnlineMetadataService.cleanSearchTitle(
            'Daft Punk - Instant Crush (Official Video) ft. Julian Casablancas'),
        'Instant Crush',
      );
    });

    test('cleanTag returns null for placeholders', () {
      expect(OnlineMetadataService.cleanTag('unknown title'), null);
      expect(OnlineMetadataService.cleanTag('Unknown Artist'), null);
      expect(OnlineMetadataService.cleanTag('unknown album'), null);
      expect(OnlineMetadataService.cleanTag('unknown'), null);
      expect(OnlineMetadataService.cleanTag('Beach Weather'), 'Beach Weather');
      expect(
          OnlineMetadataService.cleanTag('  Beach Weather  '), 'Beach Weather');
    });
  });
}
