import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/services/import_options.dart';
import 'package:wispie/services/storage_service.dart';

/// Guards the class of bug where a setting is exported into a backup but no
/// import category claims it, so restoring silently drops it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every exported setting is importable or explicitly identity-only',
      () async {
    SharedPreferences.setMockInitialValues({});

    final importable = StorageService.importableSettingsKeys.toSet();
    final identity = StorageService.identitySettingsKeys.toSet();

    final unclaimed = <String>[];
    for (final key in StorageService.settingsKeys) {
      if (!importable.contains(key) && !identity.contains(key)) {
        unclaimed.add(key);
      }
    }

    expect(
      unclaimed,
      isEmpty,
      reason: 'These keys are backed up but no import category applies them. '
          'Add each to a category list in StorageService, or to '
          'identitySettingsKeys if it must never be imported.',
    );
  });

  test('no setting is claimed by more than one category', () {
    final seen = <String>{};
    final duplicates = <String>[];
    for (final key in StorageService.importableSettingsKeys) {
      if (!seen.add(key)) duplicates.add(key);
    }
    expect(duplicates, isEmpty);
  });

  test('importing every settings category applies all importable keys',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();

    // A plausible value per key type, keyed off what the app stores today.
    final exported = <String, dynamic>{
      for (final key in StorageService.importableSettingsKeys)
        key: _sampleValue(key),
    };

    const allSettingsCategories = ImportOptions(categories: {
      ImportDataCategory.themeSettings,
      ImportDataCategory.scannerSettings,
      ImportDataCategory.playbackSettings,
      ImportDataCategory.uiSettings,
      ImportDataCategory.backupSettings,
    });

    await storage.importSettingsWithOptions(exported, allSettingsCategories);

    final prefs = await SharedPreferences.getInstance();
    final missing = StorageService.importableSettingsKeys
        .where((key) => prefs.get(key) == null)
        .toList();
    expect(missing, isEmpty);
  });
}

Object _sampleValue(String key) {
  switch (key) {
    case 'music_folders_list':
    case 'excluded_folders':
    case 'auto_backup_content_types':
      return <String>['sample'];
    case 'minimum_file_size_bytes':
    case 'minimum_track_duration_ms':
    case 'play_fade_duration':
    case 'pause_fade_duration':
    case 'fade_in_duration':
    case 'fade_out_duration':
    case 'delay_duration':
    case 'gap_resume_timestamp':
    case 'auto_backup_frequency_hours':
    case 'auto_backup_delete_after_days':
    case 'player_motion_intensity':
    case 'player_motion_latency_ms':
      return 1;
    case 'player_motion_custom_intensity':
      return 0.5;
    default:
      return 'sample';
  }
}
