import Flutter
import UIKit
import UniformTypeIdentifiers
import Security
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let folderAccessManager = IOSFolderAccessManager()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "gru_songs/ios_folder_access",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.folderAccessManager.handle(call, result: result, presenter: controller)
      }
    }

    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playAndRecord,
        mode: .moviePlayback,
        options: [.defaultToSpeaker, .mixWithOthers]
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

  private func resolve(record: FolderBookmarkRecord) throws -> FolderBookmarkRecord {
    guard let bookmarkData = Data(base64Encoded: record.bookmarkDataBase64) else {
      throw NSError(domain: "WispieFolders", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid bookmark data"])
    }

    var stale = false
    let url = try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope],
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
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      updated.bookmarkDataBase64 = refreshed.base64EncodedString()
    }
    return updated
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
      options: [.withSecurityScope],
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
    let removedRecords = records.filter { $0.path == url.path }
    for record in removedRecords {
      activeAccess[record.id]?.stopAccessingSecurityScopedResource()
      activeAccess.removeValue(forKey: record.id)
    }
    records.removeAll { $0.path == url.path }
    records.append(record)
    try saveRecords(records)
    _ = url.startAccessingSecurityScopedResource()
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
