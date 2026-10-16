package io.github.kidixdev.aikatsu

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var exportResult: MethodChannel.Result? = null
    private var exportContents = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
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
        exportResult?.error("EXPORT_CANCELLED", "The log export was closed", null)
        exportResult = null
        exportContents = ""
        super.onDestroy()
    }

    companion object {
        private const val EXPORT_LOG = 701
    }
}
