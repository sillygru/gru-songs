package com.sillygru.gru_songs

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private val channelName = "gru_songs/storage"
    private val appChannelName = "gru_songs/app"
    private val requestPickTree = 9001
    private var pendingResult: MethodChannel.Result? = null
    private lateinit var volumeMonitorPlugin: VolumeMonitorPlugin

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize volume monitor plugin
        volumeMonitorPlugin = VolumeMonitorPlugin()
        volumeMonitorPlugin.initialize(flutterEngine, this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTree" -> handlePickTree(result)
                    "createFolder" -> handleCreateFolder(call.arguments as Map<*, *>, result)
                    "moveFile" -> handleMoveFile(call.arguments as Map<*, *>, result)
                    "moveFolder" -> handleMoveFolder(call.arguments as Map<*, *>, result)
                    "renameFile" -> handleRenameFile(call.arguments as Map<*, *>, result)
                    "deleteFile" -> handleDeleteFile(call.arguments as Map<*, *>, result)
                    "writeFileFromPath" -> handleWriteFileFromPath(call.arguments as Map<*, *>, result)
                    "readFile" -> handleReadFile(call.arguments as Map<*, *>, result)
                    else -> result.notImplemented()
                }
            }

        // App control channel (restart, etc.)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "restartApp" -> handleRestartApp(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleRestartApp(result: MethodChannel.Result) {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                finishAffinity()
                Runtime.getRuntime().exit(0)
                result.success(true)
            } else {
                result.error("no_intent", "Could not get launch intent", null)
            }
        } catch (e: Exception) {
            result.error("restart_failed", e.message, null)
        }
    }

    private fun handlePickTree(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("in_progress", "Another picker is active", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        startActivityForResult(intent, requestPickTree)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == requestPickTree) {
            val result = pendingResult
            pendingResult = null

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                val flags = data.flags and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                contentResolver.takePersistableUriPermission(uri, flags)
                val path = treeUriToPath(uri)
                result?.success(mapOf("treeUri" to uri.toString(), "path" to path))
            } else {
                result?.success(null)
            }
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    private fun handleCreateFolder(args: Map<*, *>, result: MethodChannel.Result) {
        val treeUri = args["treeUri"] as? String
        val relativePath = args["relativePath"] as? String
        if (treeUri.isNullOrBlank() || relativePath.isNullOrBlank()) {
            result.error("invalid_args", "treeUri and relativePath required", null)
            return
        }

        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
        if (root == null) {
            result.error("invalid_tree", "Unable to access tree URI", null)
            return
        }

        val created = findOrCreateDirectory(root, relativePath)
        if (created == null) {
            result.error("create_failed", "Unable to create folder", null)
        } else {
            result.success(true)
        }
    }

    private fun handleMoveFile(args: Map<*, *>, result: MethodChannel.Result) {
        val treeUri = args["treeUri"] as? String
        val sourceRelativePath = args["sourceRelativePath"] as? String
        val targetRelativeDir = args["targetRelativeDir"] as? String
        val targetFileName = args["targetFileName"] as? String

        if (treeUri.isNullOrBlank() || sourceRelativePath.isNullOrBlank() || targetRelativeDir == null) {
            result.error("invalid_args", "treeUri/sourceRelativePath/targetRelativeDir required", null)
            return
        }

        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
        if (root == null) {
            result.error("invalid_tree", "Unable to access tree URI", null)
            return
        }

        val source = findDocument(root, sourceRelativePath)
        if (source == null || !source.isFile) {
            result.error("not_found", "Source file not found", null)
            return
        }

        val targetDir = if (targetRelativeDir.isBlank()) root else findOrCreateDirectory(root, targetRelativeDir)
        if (targetDir == null) {
            result.error("target_missing", "Target directory not found", null)
            return
        }

        val fileName = targetFileName ?: (source.name ?: "file")
        val type = source.type ?: "application/octet-stream"
        val dest = targetDir.createFile(type, fileName)
        if (dest == null) {
            result.error("create_failed", "Unable to create destination file", null)
            return
        }

        val copied = copyDocument(source, dest)
        if (!copied) {
            result.error("copy_failed", "Failed to copy file", null)
            return
        }

        source.delete()
        result.success(true)
    }

    private fun handleMoveFolder(args: Map<*, *>, result: MethodChannel.Result) {
        val treeUri = args["treeUri"] as? String
        val sourceRelativePath = args["sourceRelativePath"] as? String
        val targetParentRelativePath = args["targetParentRelativePath"] as? String

        if (treeUri.isNullOrBlank() || sourceRelativePath.isNullOrBlank() || targetParentRelativePath.isNullOrBlank()) {
            result.error("invalid_args", "treeUri/sourceRelativePath/targetParentRelativePath required", null)
            return
        }

        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
        if (root == null) {
            result.error("invalid_tree", "Unable to access tree URI", null)
            return
        }

        val source = findDocument(root, sourceRelativePath)
        if (source == null || !source.isDirectory) {
            result.error("not_found", "Source folder not found", null)
            return
        }

        val targetParent = findOrCreateDirectory(root, targetParentRelativePath)
        if (targetParent == null) {
            result.error("target_missing", "Target parent not found", null)
            return
        }

        val folderName = source.name ?: "folder"
        val destFolder = targetParent.createDirectory(folderName)
        if (destFolder == null) {
            result.error("create_failed", "Unable to create destination folder", null)
            return
        }

        val copied = copyDirectory(source, destFolder)
        if (!copied) {
            result.error("copy_failed", "Failed to copy folder", null)
            return
        }

        source.delete()
        result.success(true)
    }

    private fun handleRenameFile(args: Map<*, *>, result: MethodChannel.Result) {
        val treeUri = args["treeUri"] as? String
        val sourceRelativePath = args["sourceRelativePath"] as? String
        val newName = args["newName"] as? String

        if (treeUri.isNullOrBlank() || sourceRelativePath.isNullOrBlank() || newName.isNullOrBlank()) {
            result.error("invalid_args", "treeUri/sourceRelativePath/newName required", null)
            return
        }

        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
        if (root == null) {
            result.error("invalid_tree", "Unable to access tree URI", null)
            return
        }

        val source = findDocument(root, sourceRelativePath)
        if (source == null || !source.isFile) {
            result.error("not_found", "Source file not found", null)
            return
        }

        val renamed = source.renameTo(newName)
        if (!renamed) {
            result.error("rename_failed", "Failed to rename file", null)
        } else {
            result.success(true)
        }
    }

    private fun handleDeleteFile(args: Map<*, *>, result: MethodChannel.Result) {
        val treeUri = args["treeUri"] as? String
        val sourceRelativePath = args["sourceRelativePath"] as? String

        if (treeUri.isNullOrBlank() || sourceRelativePath.isNullOrBlank()) {
            result.error("invalid_args", "treeUri/sourceRelativePath required", null)
            return
        }

        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
        if (root == null) {
            result.error("invalid_tree", "Unable to access tree URI", null)
            return
        }

        val source = findDocument(root, sourceRelativePath)
        if (source == null || !source.isFile) {
            result.error("not_found", "Source file not found", null)
            return
        }

        val deleted = source.delete()
        if (!deleted) {
            result.error("delete_failed", "Failed to delete file", null)
        } else {
            result.success(true)
        }
    }

    private fun handleWriteFileFromPath(args: Map<*, *>, result: MethodChannel.Result) {
        val treeUri = args["treeUri"] as? String
        val sourceRelativePath = args["sourceRelativePath"] as? String
        val sourcePath = args["sourcePath"] as? String

        if (treeUri.isNullOrBlank() || sourceRelativePath.isNullOrBlank() || sourcePath.isNullOrBlank()) {
            result.error("invalid_args", "treeUri/sourceRelativePath/sourcePath required", null)
            return
        }

        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
        if (root == null) {
            result.error("invalid_tree", "Unable to access tree URI", null)
            return
        }

        val cleanPath = sourceRelativePath.trim('/')
        val fileName = cleanPath.substringAfterLast('/')
        val parentPath = cleanPath.substringBeforeLast('/', "")
        val parent = findOrCreateDirectory(root, parentPath)
        if (parent == null) {
            result.error("target_missing", "Target directory not found", null)
            return
        }

        val existing = parent.findFile(fileName)
        val mimeType = guessMimeType(fileName)

        // Write to a temp file first to avoid corrupting the original on partial writes.
        val tempName = "$fileName.tmp"
        parent.findFile(tempName)?.delete()
        val tempTarget = parent.createFile(mimeType, tempName)
        if (tempTarget == null) {
            result.error("create_failed", "Unable to create temp file", null)
            return
        }

        try {
            File(sourcePath).inputStream().use { input ->
                contentResolver.openOutputStream(tempTarget.uri, "w")?.use { output ->
                    input.copyTo(output)
                } ?: run {
                    result.error("write_failed", "Unable to open output stream", null)
                    return
                }
            }
            if (existing != null && !existing.delete()) {
                result.error("delete_failed", "Failed to delete existing file", null)
                tempTarget.delete()
                return
            }
            val renamed = tempTarget.renameTo(fileName)
            if (!renamed) {
                result.error("rename_failed", "Failed to rename temp file", null)
                tempTarget.delete()
                return
            }
            result.success(true)
        } catch (e: Exception) {
            tempTarget.delete()
            result.error("write_failed", "Failed to write file", e.message)
        }
    }

    private fun handleReadFile(args: Map<*, *>, result: MethodChannel.Result) {
        val treeUri = args["treeUri"] as? String
        val relativePath = args["relativePath"] as? String

        if (treeUri.isNullOrBlank() || relativePath.isNullOrBlank()) {
            result.error("invalid_args", "treeUri and relativePath required", null)
            return
        }

        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
        if (root == null) {
            result.error("invalid_tree", "Unable to access tree URI", null)
            return
        }

        val document = findDocument(root, relativePath)
        if (document == null || !document.isFile) {
            result.error("not_found", "File not found", null)
            return
        }

        try {
            contentResolver.openInputStream(document.uri)?.use { input ->
                val content = input.bufferedReader().use { it.readText() }
                result.success(content)
            } ?: run {
                result.error("read_failed", "Unable to open input stream", null)
            }
        } catch (e: Exception) {
            result.error("read_failed", "Failed to read file: ${e.message}", null)
        }
    }

    private fun treeUriToPath(uri: Uri): String? {
        val docId = DocumentsContract.getTreeDocumentId(uri)
        val parts = docId.split(":")
        if (parts.isEmpty()) return null

        val volume = parts[0]
        val rel = if (parts.size > 1) parts[1] else ""
        return if (volume == "primary") {
            val base = Environment.getExternalStorageDirectory().path
            if (rel.isEmpty()) base else "$base/$rel"
        } else {
            val storageRoot = File("/storage/$volume")
            if (!storageRoot.exists()) return null
            if (rel.isEmpty()) storageRoot.path else "${storageRoot.path}/$rel"
        }
    }

    private fun findDocument(root: DocumentFile, relativePath: String): DocumentFile? {
        val clean = relativePath.trim('/').takeIf { it.isNotEmpty() } ?: return root
        var current: DocumentFile? = root
        for (segment in clean.split('/')) {
            current = current?.findFile(segment)
            if (current == null) return null
        }
        return current
    }

    private fun findOrCreateDirectory(root: DocumentFile, relativePath: String): DocumentFile? {
        val clean = relativePath.trim('/').takeIf { it.isNotEmpty() } ?: return root
        var current: DocumentFile? = root
        for (segment in clean.split('/')) {
            var next = current?.findFile(segment)
            if (next == null) {
                next = current?.createDirectory(segment)
            }
            if (next == null) return null
            current = next
        }
        return current
    }

    private fun copyDocument(source: DocumentFile, dest: DocumentFile): Boolean {
        return try {
            contentResolver.openInputStream(source.uri)?.use { input ->
                contentResolver.openOutputStream(dest.uri, "w")?.use { output ->
                    input.copyTo(output)
                }
            } ?: return false
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun copyDirectory(source: DocumentFile, dest: DocumentFile): Boolean {
        for (child in source.listFiles()) {
            if (child.isDirectory) {
                val dirName = child.name ?: return false
                val newDir = dest.createDirectory(dirName) ?: return false
                if (!copyDirectory(child, newDir)) return false
            } else if (child.isFile) {
                val fileName = child.name ?: return false
                val type = child.type ?: "application/octet-stream"
                val newFile = dest.createFile(type, fileName) ?: return false
                if (!copyDocument(child, newFile)) return false
            }
        }
        return true
    }

    private fun guessMimeType(fileName: String): String {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
        return mimeType ?: "application/octet-stream"
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::volumeMonitorPlugin.isInitialized) {
            volumeMonitorPlugin.cleanup()
        }
    }
}
