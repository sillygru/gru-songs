import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gru_songs/services/storage_service.dart';
import 'package:gru_songs/services/import_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService - Granular Settings Import', () {
    late StorageService storageService;

    setUp(() {
      storageService = StorageService();
      SharedPreferences.setMockInitialValues({});
    });

    group('importThemeSettings', () {
      test('imports theme settings correctly', () async {
        final settings = {
          'theme_mode': 'dark',
          'use_cover_color': true,
          'apply_cover_color_to_all': false,
        };

        await storageService.importThemeSettings(settings);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode'), 'dark');
        expect(prefs.getBool('use_cover_color'), true);
        expect(prefs.getBool('apply_cover_color_to_all'), false);
      });

      test('skips missing theme settings', () async {
        final settings = {
          'theme_mode': 'light',
        };

        await storageService.importThemeSettings(settings);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode'), 'light');
        expect(prefs.getBool('use_cover_color'), isNull);
      });
    });

    group('importScannerSettings', () {
      test('imports scanner settings correctly', () async {
        final settings = {
          'music_folders_list': ['/music'],
          'excluded_folders': ['/music/excluded'],
          'last_library_folder': '/music',
          'minimum_file_size_bytes': 102400,
          'minimum_track_duration_ms': 10000,
          'include_videos': true,
        };

        await storageService.importScannerSettings(settings);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('music_folders_list'), ['/music']);
        expect(prefs.getStringList('excluded_folders'), ['/music/excluded']);
        expect(prefs.getString('last_library_folder'), '/music');
        expect(prefs.getInt('minimum_file_size_bytes'), 102400);
        expect(prefs.getInt('minimum_track_duration_ms'), 10000);
        expect(prefs.getBool('include_videos'), true);
      });
    });

    group('importPlaybackSettings', () {
      test('imports playback settings correctly', () async {
        final settings = {
          'play_fade_duration': 0.5,
          'pause_fade_duration': 0.3,
          'gap_song_id': 'test_song',
          'gap_resume_timestamp': 12345,
          'gap_is_active': true,
        };

        await storageService.importPlaybackSettings(settings);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getDouble('play_fade_duration'), 0.5);
        expect(prefs.getDouble('pause_fade_duration'), 0.3);
        expect(prefs.getString('gap_song_id'), 'test_song');
        expect(prefs.getInt('gap_resume_timestamp'), 12345);
        expect(prefs.getBool('gap_is_active'), true);
      });
    });

    group('importUISettings', () {
      test('imports UI settings correctly', () async {
        final settings = {
          'sort_order': 1,
          'visualizer_enabled': false,
          'auto_hide_bottom_bar_on_scroll': true,
          'show_song_duration': true,
          'animated_sound_wave_enabled': false,
          'show_waveform': true,
          'quick_action_config': '{"key": "value"}',
          'cover_sizing_mode': 2,
          'pull_to_refresh_enabled': false,
        };

        await storageService.importUISettings(settings);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('sort_order'), 1);
        expect(prefs.getBool('visualizer_enabled'), false);
        expect(prefs.getBool('auto_hide_bottom_bar_on_scroll'), true);
        expect(prefs.getBool('show_song_duration'), true);
        expect(prefs.getBool('animated_sound_wave_enabled'), false);
        expect(prefs.getBool('show_waveform'), true);
        expect(prefs.getString('quick_action_config'), '{"key": "value"}');
        expect(prefs.getInt('cover_sizing_mode'), 2);
        expect(prefs.getBool('pull_to_refresh_enabled'), false);
      });
    });

    group('importBackupSettings', () {
      test('imports backup settings correctly', () async {
        final settings = {
          'auto_backup_frequency_hours': 24,
          'auto_backup_delete_after_days': 7,
        };

        await storageService.importBackupSettings(settings);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('auto_backup_frequency_hours'), 24);
        expect(prefs.getInt('auto_backup_delete_after_days'), 7);
      });
    });

    group('importSettingsWithOptions', () {
      test('imports only selected categories', () async {
        final settings = {
          'theme_mode': 'dark',
          'sort_order': 2,
          'auto_backup_frequency_hours': 12,
          'play_fade_duration': 0.5,
        };

        await storageService.importSettingsWithOptions(
          settings,
          ImportOptions(
            categories: {
              ImportDataCategory.themeSettings,
              ImportDataCategory.uiSettings,
            },
          ),
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode'), 'dark');
        expect(prefs.getInt('sort_order'), 2);
        expect(prefs.getInt('auto_backup_frequency_hours'), isNull);
        expect(prefs.getDouble('play_fade_duration'), isNull);
      });

      test('imports multiple selected categories', () async {
        final settings = {
          'theme_mode': 'light',
          'sort_order': 1,
          'auto_backup_frequency_hours': 24,
          'play_fade_duration': 0.3,
        };

        await storageService.importSettingsWithOptions(
          settings,
          ImportOptions(
            categories: {
              ImportDataCategory.themeSettings,
              ImportDataCategory.scannerSettings,
              ImportDataCategory.backupSettings,
            },
          ),
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode'), 'light');
        expect(prefs.getInt('sort_order'), isNull);
        expect(prefs.getInt('auto_backup_frequency_hours'), 24);
        expect(prefs.getDouble('play_fade_duration'), isNull);
      });

      test('handles empty categories gracefully', () async {
        final settings = {
          'theme_mode': 'dark',
        };

        await storageService.importSettingsWithOptions(
          settings,
          ImportOptions(categories: {}),
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode'), isNull);
      });
    });
  });
}
