package ru.larincold.larin_cold_gsm_control

import android.Manifest
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingPermission: MethodChannel.Result? = null
    private val prefs by lazy { getSharedPreferences("larin_sms", MODE_PRIVATE) }
    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "messages") runOnUiThread { channel?.invokeMethod("smsChanged", null) }
    }
    private fun allowed(): Boolean = Build.VERSION.SDK_INT < 23 ||
        checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ru.larincold/sms")
        prefs.registerOnSharedPreferenceChangeListener(listener)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val number = normalizedSender(call.argument<String>("number") ?: "")
                    if (number != prefs.getString("device", "")) {
                        prefs.edit().putString("device", number).remove("messages").commit()
                    }
                    result.success(null)
                }
                "snapshot" -> result.success(mapOf(
                    "allowed" to allowed(),
                    "messages" to if (allowed()) prefs.getString("messages", "[]") else "[]"
                ))
                "requestPermission" -> {
                    if (allowed()) result.success(true)
                    else if (pendingPermission != null) result.error("busy", "Permission request in progress", null)
                    else {
                        pendingPermission = result
                        requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), 148)
                    }
                }
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName")))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 148) {
            pendingPermission?.success(allowed())
            pendingPermission = null
        }
    }
    override fun onDestroy() {
        prefs.unregisterOnSharedPreferenceChangeListener(listener)
        channel?.setMethodCallHandler(null)
        channel = null
        pendingPermission?.success(false)
        pendingPermission = null
        super.onDestroy()
    }
}
