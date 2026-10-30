package ru.larincold.larin_cold_gsm_control
import android.Manifest
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var smsPending: MethodChannel.Result? = null
    private var smsChannel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private fun allowed() = (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
    private fun smsAllowed() = checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
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

        // Приём ответов модуля (RECEIVE_SMS). Текст разбирает Dart.
        val sms = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ru.larincold/sms")
        smsChannel = sms
        SmsInbox.listener = { main.post { smsChannel?.invokeMethod("inboxChanged", null) } }
        sms.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "setDevices" -> {
                        SmsInbox.setDevices(this, call.argument<List<String>>("numbers") ?: emptyList(),
                            call.argument<List<Map<*, *>>>("cars") ?: emptyList())
                        result.success(null)
                    }
                    "forget" -> { SmsInbox.forget(this, call.argument<String>("number") ?: ""); result.success(null) }
                    "drain" -> result.success(SmsInbox.drain(this, (call.argument<Number>("after") ?: 0).toLong()))
                    "ack" -> { SmsInbox.ack(this, (call.argument<Number>("seq") ?: 0).toLong()); result.success(null) }
                    "state" -> result.success(mapOf(
                        "granted" to smsAllowed(),
                        "manufacturer" to Build.MANUFACTURER.lowercase(),
                        "brand" to Build.BRAND.lowercase(),
                        "model" to Build.MODEL,
                        "sdk" to Build.VERSION.SDK_INT,
                        "notifications" to allowed(),
                        "battery" to batteryUnrestricted(),
                        "installer" to (installerPackage() ?: ""),
                        "bgReplyAt" to SmsInbox.prefs(this).getLong("bgReplyAt", 0L)))
                    "open" -> result.success(PhoneScreens.open(this, call.argument<String>("kind") ?: "app"))
                    "compose" -> {
                        // Обычный startActivity (не ForResult): иначе Samsung «Сообщения» отвечают
                        // «Не удаётся начать разговор» и оставляют поверх приложения пустое окно.
                        val body = call.argument<String>("body") ?: ""
                        val i = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:" + (call.argument<String>("number") ?: "")))
                            .putExtra("sms_body", body)
                            .putExtra(Intent.EXTRA_TEXT, body)
                        result.success(try { startActivity(i); true } catch (e: Exception) { false })
                    }
                    "request" -> {
                        if (smsAllowed()) result.success(true)
                        else if (smsPending != null) result.success(false)
                        else { smsPending = result; requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), 150) }
                    }
                    "appSettings" -> {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("sms", e.message, null) }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if(requestCode==149){pending?.success(allowed());pending=null}
        if(requestCode==150){smsPending?.success(smsAllowed());smsPending=null}
    }
    private fun batteryUnrestricted(): Boolean =
        (getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)

    /** Кто установил приложение: магазин (RuStore и т. п.) или системный установщик из файла. */
    private fun installerPackage(): String? = try {
        if (Build.VERSION.SDK_INT >= 30) packageManager.getInstallSourceInfo(packageName).installingPackageName
        else packageManager.getInstallerPackageName(packageName)
    } catch (_: Exception) { null }

    override fun onResume() { super.onResume(); SmsInbox.foreground = true }
    override fun onPause() { SmsInbox.foreground = false; super.onPause() }
    override fun onDestroy(){
        pending?.success(false);pending=null
        smsPending?.success(false);smsPending=null
        SmsInbox.listener = null; smsChannel = null
        super.onDestroy()
    }
}

/**
 * Экраны системы и оболочек производителей, куда приложение ведёт пользователя
 * при настройке. Каждый вариант пробуется по очереди; если ни один не открылся —
 * «Сведения о приложении» (там есть всё, просто глубже).
 */
object PhoneScreens {
    private fun details(c: Context) = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${c.packageName}"))

    private fun tryStart(c: Context, intents: List<Intent>): Boolean {
        for (i in intents) {
            try {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                c.startActivity(i)
                return true
            } catch (_: Exception) { }
        }
        return false
    }

    private fun comp(pkg: String, cls: String) = Intent().setComponent(ComponentName(pkg, cls))

    /** true — открыт специальный экран; false — открыты «Сведения о приложении». */
    fun open(c: Context, kind: String): Boolean {
        val pkg = c.packageName
        val list: List<Intent> = when (kind) {
            "notifications" -> listOf(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg))
            "battery" -> listOf(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            "miuiActivity" -> listOf(
                comp("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity")
                    .putExtra("package_name", pkg).putExtra("package_label", "Larin Cold Start"))
            "autostart" -> listOf(
                comp("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
                comp("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                comp("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
                comp("com.hihonor.systemmanager", "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                comp("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
                comp("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
                comp("com.oplus.safecenter", "com.oplus.safecenter.permission.startup.StartupAppListActivity"),
                comp("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
                comp("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
                comp("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"))
            else -> emptyList()
        }
        if (tryStart(c, list)) return true
        tryStart(c, listOf(details(c)))
        return false
    }
}
