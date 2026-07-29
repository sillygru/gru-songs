import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wispie/services/database_service.dart';
import 'package:wispie/services/storage_service.dart';
import 'package:wispie/services/wispie_paths.dart';
import 'package:wispie/data/repositories/search_index_repository.dart';

/// Manages the test environment for tests that need file system isolation.
///
/// Creates a temporary directory for test data and ensures it's cleaned up
/// after tests complete. This prevents test database files from being
/// created in the user's Documents folder.
///
/// Usage:
/// ```dart
/// void main() {
///   late TestEnvironment testEnv;
///
///   setUpAll(() {
///     testEnv = TestEnvironment();
///     testEnv.setUp();
///   });
///
///   tearDownAll(() {
///     testEnv.tearDown();
///   });
///
///   // ... tests
/// }
/// ```
class TestEnvironment {
  Directory? _tempDir;
  static const MethodChannel _channel =
      MethodChannel('plugins.flutter.io/path_provider');

  /// Creates the temporary directory and sets up method channel mocks.
  void setUp() {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Create a real temporary directory for test files
    _tempDir = Directory.systemTemp.createTempSync('wispie_test_');

    // Initialize SQLite for testing
    sqfliteFfiInit();
    // Reset to null first to suppress the sqflite warning about changing
    // the default factory. This is intentional for test environment setup.
    databaseFactory = null;
    databaseFactory = databaseFactoryFfi;

    // Mock path_provider via MethodChannel - this is more reliable than
    // platform mocking because it intercepts calls before caching
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return _tempDir!.path;
      }
      if (methodCall.method == 'getTemporaryPath') {
        return _tempDir!.path;
      }
      if (methodCall.method == 'getLibraryPath') {
        return _tempDir!.path;
      }
      if (methodCall.method == 'getApplicationSupportPath') {
        return _tempDir!.path;
      }
      if (methodCall.method == 'getExternalStoragePath') {
        return _tempDir!.path;
      }
      if (methodCall.method == 'getDownloadsPath') {
        return _tempDir!.path;
      }
      return null;
    });

    // Also mock the platform interface as a backup. Save original so
    // tearDown can restore it.
    _originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _MockPathProviderPlatform(_tempDir!.path);

    // Mock the volume monitoring channel to prevent MissingPluginException
    // when AudioPlayerManager initializes VolumeMonitorService.
    final volumeChannel = MethodChannel('wispie/volume');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(volumeChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'getCurrentVolume') {
        return 1.0;
      }
      return null;
    });
    // Mock the volume event channel to prevent unhandled stream errors.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'wispie/volume_events',
      (ByteData? message) async => null,
    );

    // Mock SharedPreferences
    SharedPreferencesStorePlatform.instance = MockSharedPreferencesStore();

    // Belt-and-suspenders: override path-based services directly so they
    // cannot write to the real Documents folder even if the method channel
    // or platform interface mock fails.
    testWispiePath = _tempDir!.path;
    SearchIndexRepository.testDocumentsPath = _tempDir!.path;
    StorageService.testDocumentsPath = _tempDir!.path;
  }

  PathProviderPlatform? _originalPathProvider;

  /// Cleans up the temporary directory.
  Future<void> tearDown() async {
    // Close any open databases before deleting temp directory
    await DatabaseService.instance.close();

    // Clear method channel handlers
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('wispie/volume'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'wispie/volume_events',
      null,
    );

    // Restore original path provider platform instance to avoid leaking
    // the mock into subsequent test files in the same session.
    final original = _originalPathProvider;
    if (original != null) {
      PathProviderPlatform.instance = original;
      _originalPathProvider = null;
    }

    // Clear static path overrides and reset the search index database
    // handle so the next test file starts fresh.
    testWispiePath = null;
    SearchIndexRepository.testDocumentsPath = null;
    SearchIndexRepository.resetDatabase();
    StorageService.testDocumentsPath = null;

    // Clean up temp directory
    if (_tempDir != null && _tempDir!.existsSync()) {
      try {
        _tempDir!.deleteSync(recursive: true);
      } catch (e) {
        // Ignore cleanup errors in tests
        debugPrint('Warning: Failed to clean up test temp directory: $e');
      }
      _tempDir = null;
    }
  }

  /// Returns the path to the temporary directory.
  String get tempPath => _tempDir?.path ?? '';
}

// Mock PathProviderPlatform that returns the temp directory path
class _MockPathProviderPlatform extends PathProviderPlatform {
  final String _tempPath;

  _MockPathProviderPlatform(this._tempPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => _tempPath;

  @override
  Future<String?> getTemporaryPath() async => _tempPath;

  @override
  Future<String?> getLibraryPath() async => _tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => _tempPath;

  @override
  Future<String?> getExternalStoragePath() async => _tempPath;

  @override
  Future<List<String>?> getExternalCachePaths() async => [_tempPath];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      [_tempPath];

  @override
  Future<String?> getDownloadsPath() async => _tempPath;
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
  Future<Map<String, Object>> getAll() async => Map.from(_storage);

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
