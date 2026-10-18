package io.github.kidixdev.aikatsu

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var exportResult: MethodChannel.Result? = null
    private var exportContents = ""
    private var folderResult: MethodChannel.Result? = null
    private var audio: MethodChannel? = null

    // Headphones unplugged or Bluetooth audio gone: the player pauses instead of going on through the speaker.
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            audio?.invokeMethod("noisy", null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audio = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.kidixdev.aikatsu/audio")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.kidixdev.aikatsu/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url"))))
                        result.success(null)
                    }
                    // Android asks once to let Aikatsu install apps; when it hasn't, that setting opens instead.
                    "canInstall" -> {
                        val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
                        if (!allowed) startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                        result.success(allowed)
                    }
                    "install" -> {
                        val apk = File(call.argument<String>("path") ?: "")
                        Thread {
                            try {
                                installApk(apk)
                                runOnUiThread { result.success(null) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("INSTALL_FAILED", e.message, null) }
                            } finally {
                                apk.delete() // the session keeps its own copy
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.kidixdev.aikatsu/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickFolder") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (folderResult != null) {
                    result.error("BUSY", "A folder picker is already open", null)
                    return@setMethodCallHandler
                }
                folderResult = result
                val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.READ_MEDIA_VIDEO else Manifest.permission.READ_EXTERNAL_STORAGE
                if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) openFolderPicker()
                else requestPermissions(arrayOf(permission), READ_VIDEOS)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.kidixdev.aikatsu/logs")
            .setMethodCallHandler { call, result ->
                if (call.method != "exportLog") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val contents = call.argument<String>("contents")
                if (contents == null) {
                    result.error("INVALID_ARGUMENT", "Log contents are missing", null)
                    return@setMethodCallHandler
                }
                if (exportResult != null) {
                    result.error("BUSY", "A log export is already open", null)
                    return@setMethodCallHandler
                }
                exportResult = result
                exportContents = contents
                try {
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TITLE, "aikatsu-log.txt")
                    }, EXPORT_LOG)
                } catch (e: Exception) {
                    exportResult = null
                    exportContents = ""
                    result.error("EXPORT_FAILED", e.message, null)
                }
            }
    }

    private fun installApk(apk: File) {
        val installer = packageManager.packageInstaller
        val id = installer.createSession(PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL))
        installer.openSession(id).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("aikatsu.apk", 0, apk.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            // The installer reports back through onNewIntent; it adds its status, hence mutable.
            val status = Intent(this, MainActivity::class.java).setAction(INSTALL_STATUS)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            session.commit(PendingIntent.getActivity(this, 0, status, flags).intentSender)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action != INSTALL_STATUS) return
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)?.let { startActivity(it) }
            }
            PackageInstaller.STATUS_SUCCESS, PackageInstaller.STATUS_FAILURE_ABORTED -> {}
            else -> Toast.makeText(this, intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "The update wasn't installed", Toast.LENGTH_LONG).show()
        }
    }

    private fun openFolderPicker() {
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), PICK_FOLDER)
        } catch (e: Exception) {
            folderResult?.error("PICK_FAILED", e.message, null)
            folderResult = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != READ_VIDEOS) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            openFolderPicker()
        } else {
            folderResult?.error("NO_PERMISSION", "Allow Aikatsu to read your videos to add a folder", null)
            folderResult = null
        }
    }

    private fun folderPicked(resultCode: Int, data: Intent?) {
        val result = folderResult ?: return
        folderResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val path = treePath(uri)
        if (path == null) result.error("NOT_A_FOLDER", "Pick a folder on this phone's storage or SD card", null) else result.success(path)
    }

    @Suppress("DEPRECATION")
    private fun treePath(uri: Uri): String? {
        if (uri.authority != "com.android.externalstorage.documents") return null
        val parts = DocumentsContract.getTreeDocumentId(uri).split(":", limit = 2)
        val base = if (parts[0].equals("primary", ignoreCase = true)) Environment.getExternalStorageDirectory().path else "/storage/${parts[0]}"
        val rel = parts.getOrElse(1) { "" }
        return if (rel.isEmpty()) base else "$base/$rel"
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_FOLDER) {
            folderPicked(resultCode, data)
            return
        }
        if (requestCode != EXPORT_LOG) return
        val result = exportResult ?: return
        val contents = exportContents
        exportResult = null
        exportContents = ""
        if (resultCode != Activity.RESULT_OK) {
            result.success(false)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.error("EXPORT_FAILED", "No destination file was selected", null)
            return
        }
        Thread {
            try {
                val output = contentResolver.openOutputStream(uri, "wt")
                    ?: error("Couldn't open the destination file")
                output.bufferedWriter(Charsets.UTF_8).use { it.write(contents) }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("EXPORT_FAILED", e.message, null) }
            }
        }.start()
    }

    override fun onDestroy() {
        unregisterReceiver(noisy)
        exportResult?.error("EXPORT_CANCELLED", "The log export was closed", null)
        exportResult = null
        exportContents = ""
        folderResult?.error("PICK_CANCELLED", "The folder picker was closed", null)
        folderResult = null
        super.onDestroy()
    }

    companion object {
        private const val EXPORT_LOG = 701
        private const val PICK_FOLDER = 702
        private const val READ_VIDEOS = 703
        private const val INSTALL_STATUS = "io.github.kidixdev.aikatsu.INSTALL_STATUS"
    }
}
