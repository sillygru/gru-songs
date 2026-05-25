import Flutter
import UIKit
import UniformTypeIdentifiers
import Security
import AVFoundation
import CommonCrypto

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let folderAccessManager = IOSFolderAccessManager()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let folderChannel = FlutterMethodChannel(
        name: "gru_songs/ios_folder_access",
        binaryMessenger: controller.binaryMessenger
      )
      folderChannel.setMethodCallHandler { [weak self] call, result in
        self?.folderAccessManager.handle(call, result: result, presenter: controller)
      }

      let mediaChannel = FlutterMethodChannel(
        name: "gru_songs/ios_media_access",
        binaryMessenger: controller.binaryMessenger
      )
      mediaChannel.setMethodCallHandler { [weak self] call, result in
        self?.handleMediaAccess(call, result: result)
      }
    }

    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.allowAirPlay]
      )
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Failed to set audio session category: \(error)")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class IOSFolderAccessManager: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private let store = IOSFolderBookmarkStore()
  private var activeAccess: [String: URL] = [:]
  private var pendingResult: FlutterResult?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult, presenter: UIViewController) {
    switch call.method {
    case "pickFolder":
      presentFolderPicker(result: result, presenter: presenter)
    case "loadResolvedFolders":
      result(loadResolvedFolders())
    case "loadPersistedFolders":
      result(loadPersistedFolders())
    case "removeFolder":
      guard let args = call.arguments as? [String: Any],
            let bookmarkId = args["bookmarkId"] as? String else {
        result(FlutterError(code: "bad_args", message: "Missing bookmarkId", details: nil))
        return
      }
      removeFolder(bookmarkId: bookmarkId)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentFolderPicker(result: @escaping FlutterResult, presenter: UIViewController) {
    pendingResult = result

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
    }

    picker.allowsMultipleSelection = false
    picker.delegate = self
    picker.presentationController?.delegate = self
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      pendingResult?(nil)
      pendingResult = nil
      return
    }

    do {
      let record = try store.upsertFolder(from: url)
      if let existing = activeAccess[record.id] {
        existing.stopAccessingSecurityScopedResource()
      }
      _ = url.startAccessingSecurityScopedResource()
      activeAccess[record.id] = url
      pendingResult?(record.toFlutterMap())
    } catch {
      pendingResult?(FlutterError(code: "bookmark_error", message: error.localizedDescription, details: nil))
    }
    pendingResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingResult?(nil)
    pendingResult = nil
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    if pendingResult != nil {
      pendingResult?(nil)
      pendingResult = nil
    }
  }

  private func loadResolvedFolders() -> [[String: Any]] {
    do {
      let records = try store.loadRecords()
      var resolved = [[String: Any]]()
      var changed = false
      var updatedRecords = [FolderBookmarkRecord]()

      for record in records {
        do {
          let resolvedRecord = try resolve(record: record)
          resolved.append(resolvedRecord.toFlutterMap())
          updatedRecords.append(resolvedRecord)
          if resolvedRecord != record {
            changed = true
          }
        } catch {
          changed = true
          activeAccess[record.id]?.stopAccessingSecurityScopedResource()
          activeAccess.removeValue(forKey: record.id)
        }
      }

      if changed {
        try? store.saveRecords(updatedRecords)
      }

      return resolved
    } catch {
      return []
    }
  }

  private func loadPersistedFolders() -> [[String: Any]] {
    do {
      return try store.loadRecords().map { $0.toFlutterMap() }
    } catch {
      return []
    }
  }

  private func removeFolder(bookmarkId: String) {
    if let url = activeAccess.removeValue(forKey: bookmarkId) {
      url.stopAccessingSecurityScopedResource()
    }
    try? store.removeRecord(bookmarkId: bookmarkId)
  }

  /// Checks whether the given file path lies inside any currently active
  /// security-scoped folder. AVFoundation cannot directly access files in
  /// security-scoped locations via a plain path string (the security scope
  /// is tied to the original URL object). If the file is scoped, we copy it
  /// to /tmp using NSFileManager (which uses APFS clone/copy-on-write on
  /// modern iOS, making it instant with zero data duplication).
  func prepareVideoPathForAccess(_ path: String) -> String? {
    let fileManager = FileManager.default
    let sourceURL = URL(fileURLWithPath: path)
    guard fileManager.fileExists(atPath: path) else { return nil }

    // Check if the file is already inside the app sandbox.
    // If so, no workaround is needed.
    if _pathIsInAppSandbox(path, fileManager: fileManager) { return path }

    // Check if the file is inside a security-scoped folder.
    // We need to verify that the current process has access granted.
    let isScoped = activeAccess.values.contains { folderURL in
      let folderPath = folderURL.path.hasSuffix("/") ? folderURL.path : folderURL.path + "/"
      return path.hasPrefix(folderPath)
    }

    if !isScoped { return path }

    // Build temp path, preserving the original extension.
    let tempDir = fileManager.temporaryDirectory
      .appendingPathComponent("wispie_video_cache", isDirectory: true)
    try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let ext = (path as NSString).pathExtension
    let hash = _sha1(path)
    let destURL = tempDir.appendingPathComponent("\(hash).\(ext)")

    // Remove stale temp file if present.
    if fileManager.fileExists(atPath: destURL.path) {
      // Verify the temp file is not older than the source.
      let srcAttrs = try? fileManager.attributesOfItem(atPath: path)
      let dstAttrs = try? fileManager.attributesOfItem(atPath: destURL.path)
      if let srcMod = srcAttrs?[.modificationDate] as? Date,
         let dstMod = dstAttrs?[.modificationDate] as? Date,
         srcMod <= dstMod {
        return destURL.path
      }
      // Stale or unreadable — remove and recreate below.
      try? fileManager.removeItem(at: destURL)
    }

    // Use NSFileManager to copy — this leverages APFS clone/copy-on-write
    // on modern iOS, which is instantaneous and shares data blocks with
    // the original until either is modified.
    do {
      try fileManager.copyItem(at: sourceURL, to: destURL)
      return destURL.path
    } catch {
      return nil
    }
  }

  private func _pathIsInAppSandbox(_ path: String, fileManager: FileManager) -> Bool {
    let sandboxPaths: [String] = [
      fileManager.temporaryDirectory.path,
      NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? "",
      NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "",
    ]
    return sandboxPaths.contains { path.hasPrefix($0) }
  }

  private func _sha1(_ string: String) -> String {
    let data = Data(string.utf8)
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
      _ = CC_SHA1(buffer.baseAddress, CC_LONG(buffer.count), &digest)
    }
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  /// Resolves a folder bookmark record to a live URL, refreshing access
  /// and handling stale bookmark data.
  private func resolve(record: FolderBookmarkRecord) throws -> FolderBookmarkRecord {
    guard let bookmarkData = Data(base64Encoded: record.bookmarkDataBase64) else {
      throw NSError(domain: "WispieFolders", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid bookmark data"])
    }

    var stale = false
    let url = try URL(
      resolvingBookmarkData: bookmarkData,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )

    if let existing = activeAccess[record.id] {
      existing.stopAccessingSecurityScopedResource()
    }
    _ = url.startAccessingSecurityScopedResource()
    activeAccess[record.id] = url

    var updated = record
    updated.path = url.path
    if stale {
      let refreshed = try url.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      updated.bookmarkDataBase64 = refreshed.base64EncodedString()
    }
    return updated
  }
}

/// Handles the `gru_songs/ios_media_access` channel for iOS media file
/// access coordination.
extension AppDelegate {
  func handleMediaAccess(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepareVideoPath":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "Missing path", details: nil))
        return
      }
      let prepared = folderAccessManager.prepareVideoPathForAccess(path)
      result(prepared)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private struct FolderBookmarkRecord: Codable, Equatable {
  var id: String
  var path: String
  var treeUri: String?
  var platform: String
  var iosBookmarkId: String?
  var bookmarkDataBase64: String

  func toFlutterMap() -> [String: Any] {
    [
      "path": path,
      "treeUri": treeUri ?? "",
      "platform": platform,
      "bookmarkId": iosBookmarkId ?? id,
      "iosBookmarkId": iosBookmarkId ?? id,
    ]
  }
}

private final class IOSFolderBookmarkStore {
  private let service = "com.sillygru.wispie.folder_bookmarks"
  private let account = "music_folders"

  func loadRecords() throws -> [FolderBookmarkRecord] {
    guard let data = try loadBlob() else { return [] }
    return try JSONDecoder().decode([FolderBookmarkRecord].self, from: data)
  }

  func saveRecords(_ records: [FolderBookmarkRecord]) throws {
    let data = try JSONEncoder().encode(records)
    try saveBlob(data)
  }

  func upsertFolder(from url: URL) throws -> FolderBookmarkRecord {
    let bookmarkData = try url.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    let bookmarkId = UUID().uuidString
    let record = FolderBookmarkRecord(
      id: bookmarkId,
      path: url.path,
      treeUri: nil,
      platform: "ios",
      iosBookmarkId: bookmarkId,
      bookmarkDataBase64: bookmarkData.base64EncodedString()
    )

    var records = try loadRecords()
    records.removeAll { $0.path == url.path }
    records.append(record)
    try saveRecords(records)
    return record
  }

  func removeRecord(bookmarkId: String) throws {
    var records = try loadRecords()
    records.removeAll { $0.id == bookmarkId }
    try saveRecords(records)
  }

  private func loadBlob() throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Unable to read folder bookmarks"])
    }
    return item as? Data
  }

  private func saveBlob(_ data: Data) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let attributes: [String: Any] = [
      kSecValueData as String: data,
    ]

    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecSuccess {
      return
    }

    if status != errSecItemNotFound {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Unable to update folder bookmarks"])
    }

    var createQuery = query
    createQuery[kSecValueData as String] = data
    let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
    guard createStatus == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(createStatus), userInfo: [NSLocalizedDescriptionKey: "Unable to save folder bookmarks"])
    }
  }
}
