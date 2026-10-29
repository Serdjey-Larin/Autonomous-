package ru.larincold.larin_cold_gsm_control
import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private fun allowed() = (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent) }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ru.larincold/alerts").setMethodCallHandler { call, result ->
            try {
                when(call.method) {
                    "permission" -> {
                        if (allowed() || Build.VERSION.SDK_INT < 33) result.success(allowed())
                        else if (pending != null) result.success(false)
                        else { pending = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),149) }
                    }
                    "exact" -> result.success(Alerts.exact(this))
                    "settings" -> { startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,packageName)); result.success(null) }
                    "exactSettings" -> { if (Build.VERSION.SDK_INT >= 31) startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,Uri.parse("package:$packageName"))); result.success(null) }
                    "selectedCar" -> { val car = intent.getStringExtra("car"); intent.removeExtra("car"); result.success(car) }
                    "restore" -> { Alerts.restore(this); result.success(null) }
                    "cancel" -> { Alerts.cancel(this,call.argument<String>("key")!!); result.success(null) }
                    "schedule" -> {
                        val row = JSONObject(call.arguments as Map<*, *>)
                        if(row.optBoolean("daily")) row.put("at",Alerts.nextTime(row.getInt("minutes")))
                        Alerts.schedule(this,row); result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch(e: Exception) { result.error("alerts",e.message,null) }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if(requestCode==149){pending?.success(allowed());pending=null}
    }
    override fun onDestroy(){pending?.success(false);pending=null;super.onDestroy()}
}
