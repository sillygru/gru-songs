import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Mock PathProviderPlatform
class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return '/tmp/test_documents';
  }

  @override
  Future<String?> getTemporaryPath() async {
    return '/tmp/test_temp';
  }

  @override
  Future<String?> getLibraryPath() async {
    return '/tmp/test_library';
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return '/tmp/test_support';
  }

  @override
  Future<String?> getExternalStoragePath() async {
    return '/tmp/test_external';
  }

  @override
  Future<List<String>?> getExternalCachePaths() async {
    return ['/tmp/test_external_cache'];
  }

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async {
    return ['/tmp/test_external_storage'];
  }

  @override
  Future<String?> getDownloadsPath() async {
    return '/tmp/test_downloads';
  }
}

// Mock SharedPreferencesStorePlatform
class MockSharedPreferencesStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> _storage = {};

  @override
  Future<bool> clear() async {
    _storage.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    return Map.from(_storage);
  }

  @override
  Future<bool> remove(String key) async {
    _storage.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _storage[key] = value;
    return true;
  }
}

void setUpMockPlugins() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Mock PathProvider
  PathProviderPlatform.instance = MockPathProviderPlatform();

  // Mock SharedPreferences
  SharedPreferencesStorePlatform.instance = MockSharedPreferencesStore();
}
