package ru.larincold.larin_cold_gsm_control

import android.app.*
import android.content.*
import android.net.Uri
import android.os.Build
import org.json.JSONObject
import java.util.Calendar

object Alerts {
    fun prefs(c: Context) = c.getSharedPreferences("larin_alerts", Context.MODE_PRIVATE)
    fun alarm(c: Context) = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    fun exact(c: Context) = Build.VERSION.SDK_INT < 31 || alarm(c).canScheduleExactAlarms()
    fun nextTime(minutes: Int): Long {
        val now = System.currentTimeMillis()
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, minutes / 60); set(Calendar.MINUTE, minutes % 60)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        if (cal.timeInMillis <= now) cal.add(Calendar.DATE, 1)
        return cal.timeInMillis
    }
    fun intent(c: Context, key: String): PendingIntent {
        val i = Intent(c, AlarmReceiver::class.java).setData(Uri.parse("larin://alarm/$key")).putExtra("key", key)
        return PendingIntent.getBroadcast(c, 0, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    fun cancel(c: Context, key: String) {
        alarm(c).cancel(intent(c, key)); prefs(c).edit().remove(key).commit()
        (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(key, 1)
    }
    fun schedule(c: Context, row: JSONObject) {
        val key = row.getString("key")
        val at = row.getLong("at")
        prefs(c).edit().putString(key, row.toString()).commit()
        val pending = intent(c, key)
        try {
            if (exact(c)) alarm(c).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            else alarm(c).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        } catch (_: SecurityException) {
            alarm(c).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
    }
    fun restore(c: Context, recalcDaily: Boolean = false) {
        for ((_, value) in prefs(c).all) {
            val row = try { JSONObject(value as String) } catch (_: Exception) { continue }
            if (row.optBoolean("daily") && (recalcDaily || row.getLong("at") <= System.currentTimeMillis()))
                row.put("at", nextTime(row.getInt("minutes")))
            if (row.getLong("at") > System.currentTimeMillis()) schedule(c, row)
            else {
                val key = row.getString("key")
                alarm(c).cancel(intent(c, key))
                prefs(c).edit().remove(key).commit()
                if (System.currentTimeMillis() - row.getLong("at") < 24 * 60 * 60 * 1000L) notify(c, row)
            }
        }
    }
    fun notify(c: Context, row: JSONObject) {
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = "larin_heating"
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(channel, "Прогрев и напоминания", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Окончание расчётного таймера и напоминание отправить START"
                enableVibration(true)
            })
        }
        if (Build.VERSION.SDK_INT >= 24 && !nm.areNotificationsEnabled()) return
        val key = row.getString("key")
        val target = Intent(c, MainActivity::class.java).setData(Uri.parse("larin://open/$key"))
            .putExtra("car", row.getString("car")).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tap = PendingIntent.getActivity(c, 0, target, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val name = row.getString("name")
        val title = if (row.optBoolean("daily")) "$name · пора прогреть" else "$name · прогрев окончен"
        val text = if (row.optBoolean("daily")) "Откройте приложение и нажмите ЗАПУСК."
            else "Время прогрева вышло. Откройте приложение, чтобы проверить состояние."
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channel) else Notification.Builder(c)
        val n = builder.setSmallIcon(R.drawable.notification_icon).setContentTitle(title).setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text)).setAutoCancel(true).setContentIntent(tap)
            .setCategory(Notification.CATEGORY_REMINDER).setPriority(Notification.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_ALL).build()
        try { nm.notify(key, 1, n) } catch (_: SecurityException) { }
    }
}
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val key = intent.getStringExtra("key") ?: return
        val raw = Alerts.prefs(context).getString(key, null) ?: return
        val row = JSONObject(raw)
        // Ignore an outdated pending broadcast after the timer has been restarted.
        if (row.getLong("at") > System.currentTimeMillis() + 1000) { Alerts.schedule(context, row); return }
        if (row.optBoolean("daily")) {
            val next = JSONObject(raw).put("at", Alerts.nextTime(row.getInt("minutes")))
            Alerts.schedule(context, next)
        } else Alerts.prefs(context).edit().remove(key).commit()
        Alerts.notify(context, row)
    }
}
class AlarmRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { Alerts.restore(context, true) }
}
