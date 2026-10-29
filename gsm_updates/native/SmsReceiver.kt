package ru.larincold.larin_cold_gsm_control

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import org.json.JSONArray
import org.json.JSONObject

/**
 * Приём ответов GSM-модулей. Пассивный: SMS-приложение по умолчанию получает
 * сообщение как обычно. Сохраняются только SMS, номер отправителя которых
 * ПОЛНОСТЬЮ совпадает с номером модуля одного из автомобилей. Разбор текста и
 * состояние — в Dart; здесь только надёжная запись в журнал.
 */
object SmsInbox {
    private const val PREFS = "larin_sms"
    private const val MAX_ROWS = 50
    private val lock = Any()

    /** Вызывается из MainActivity, пока Flutter запущен. */
    @Volatile var listener: (() -> Unit)? = null

    /** Приложение на экране — уведомление об ответе не нужно, экран обновится сам. */
    @Volatile var foreground: Boolean = false

    fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Нормализация к +E.164. Для России: 8XXXXXXXXXX и 7XXXXXXXXXX → +7XXXXXXXXXX.
     * Сравнение номеров — только полное равенство результата.
     */
    fun normalize(raw: String): String {
        var d = raw.filter { it in '0'..'9' }
        if (d.startsWith("00")) d = d.drop(2)
        if (d.length == 11 && d.startsWith("8")) d = "7" + d.drop(1)
        return if (d.length < 10) "" else "+$d"
    }

    fun setDevices(c: Context, numbers: List<String>, cars: List<Map<*, *>> = emptyList()) {
        val set = numbers.map { normalize(it) }.filter { it.isNotEmpty() }.toSortedSet()
        val info = JSONArray()
        for (car in cars) {
            val n = normalize(car["number"] as? String ?: "")
            if (n.isNotEmpty()) info.put(JSONObject().put("number", n)
                .put("id", car["id"] as? String ?: "").put("name", car["name"] as? String ?: ""))
        }
        prefs(c).edit().putString("devices", set.joinToString("\n")).putString("cars", info.toString()).commit()
    }

    /** id и название автомобиля по номеру модуля (для уведомления). */
    fun car(c: Context, number: String): Pair<String, String>? {
        val rows = try { JSONArray(prefs(c).getString("cars", "[]")) } catch (_: Exception) { return null }
        for (i in 0 until rows.length()) {
            val r = rows.getJSONObject(i)
            if (r.optString("number") == number) return r.optString("id") to r.optString("name")
        }
        return null
    }

    private fun devices(c: Context): Set<String> =
        (prefs(c).getString("devices", "") ?: "").split('\n').filter { it.isNotEmpty() }.toSet()

    /** true — новая запись; false — дубль или чужой номер. */
    fun store(c: Context, rawSender: String, body: String, smscTs: Long, receivedAt: Long): Boolean {
        val number = normalize(rawSender)
        if (number.isEmpty() || number !in devices(c)) return false
        synchronized(lock) {
            val p = prefs(c)
            val rows = try { JSONArray(p.getString("inbox", "[]")) } catch (_: Exception) { JSONArray() }
            for (i in 0 until rows.length()) {
                val r = rows.getJSONObject(i)
                if (r.optString("number") == number && r.optLong("smsc") == smscTs && r.optString("body") == body) return false
            }
            val seq = p.getLong("seq", 0L) + 1
            val keep = JSONArray()
            for (i in maxOf(0, rows.length() - (MAX_ROWS - 1)) until rows.length()) keep.put(rows.getJSONObject(i))
            keep.put(JSONObject().put("seq", seq).put("number", number).put("body", body)
                .put("smsc", smscTs).put("received", receivedAt))
            // commit(): запись должна завершиться до выхода из onReceive.
            p.edit().putLong("seq", seq).putString("inbox", keep.toString()).commit()
        }
        return true
    }

    /** Записи с seq > afterSeq, по возрастанию. */
    fun drain(c: Context, afterSeq: Long): List<Map<String, Any>> = synchronized(lock) {
        val rows = try { JSONArray(prefs(c).getString("inbox", "[]")) } catch (_: Exception) { JSONArray() }
        (0 until rows.length()).map { rows.getJSONObject(it) }
            .filter { it.optLong("seq") > afterSeq }
            .sortedBy { it.optLong("seq") }
            .map { mapOf("seq" to it.optLong("seq"), "number" to it.optString("number"),
                "body" to it.optString("body"), "smsc" to it.optLong("smsc"), "received" to it.optLong("received")) }
    }

    /** Dart подтвердил обработку — удаляем записи до ackSeq включительно. */
    fun ack(c: Context, ackSeq: Long) = synchronized(lock) {
        val p = prefs(c)
        val rows = try { JSONArray(p.getString("inbox", "[]")) } catch (_: Exception) { JSONArray() }
        val keep = JSONArray()
        for (i in 0 until rows.length()) if (rows.getJSONObject(i).optLong("seq") > ackSeq) keep.put(rows.getJSONObject(i))
        p.edit().putString("inbox", keep.toString()).commit()
        Unit
    }
}

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (parts.isNullOrEmpty()) return
        val sender = parts.first().originatingAddress ?: return
        // Многочастное SMS приходит одним событием; части от разных отправителей не склеиваем.
        if (parts.any { (it.originatingAddress ?: "") != sender }) return
        val body = parts.joinToString("") { it.messageBody ?: "" }
        if (body.isBlank()) return
        val stored = SmsInbox.store(context, sender, body, parts.first().timestampMillis, System.currentTimeMillis())
        if (!stored) return
        SmsInbox.listener?.invoke()
        if (!SmsInbox.foreground) {
            try { ReplyNotifier.handle(context, SmsInbox.normalize(sender), body) } catch (_: Exception) { }
        }
    }
}

/**
 * Уведомление об ответе модуля, когда приложение закрыто или свёрнуто, и
 * перепланирование сигнала «готов к поездке» по ответу STATUS.
 * Те же правила разбора, что в reply_parser.dart; состояние в Dart обновится
 * из журнала при следующем открытии приложения.
 */
object ReplyNotifier {
    private const val CHANNEL = "larin_replies"
    private val heater = Regex("""heater\s*:\s*(on|off)""", RegexOption.IGNORE_CASE)
    private val left = Regex("""left\s*:\s*(\d{1,3})\s*min""", RegexOption.IGNORE_CASE)
    private val time = Regex("""time\s*:\s*(\d{1,3})\s*min""", RegexOption.IGNORE_CASE)
    private val battery = Regex("""battery\s*:\s*(\d{1,2}[.,]\d)\s*v""", RegexOption.IGNORE_CASE)
    private val balanceHint = Regex("""^USSD\s*:|balans|баланс|balance""", RegexOption.IGNORE_CASE)
    private val amount = Regex("""(-?\d+(?:[.,]\d{1,2})?)\s*(?:rub|rur|руб|р(?![а-яё])|₽)""", RegexOption.IGNORE_CASE)
    private val afterHint = Regex("""(?:balans|баланс|balance)[^\d-]{0,24}(-?\d+(?:[.,]\d{1,2})?)""", RegexOption.IGNORE_CASE)

    private fun rub(v: Double): String {
        val a = kotlin.math.abs(v)
        val t = if (a == Math.rint(a)) a.toLong().toString() else String.format(java.util.Locale.ROOT, "%.2f", a).replace('.', ',')
        return (if (v < 0) "−" else "") + t + " ₽"
    }

    fun handle(c: Context, number: String, body: String) {
        val (id, rawName) = SmsInbox.car(c, number) ?: ("" to "")
        val name = rawName.ifBlank { "Автомобиль" }
        val text = body.trim()
        val h = heater.find(text)
        var title: String
        var line: String
        if (h != null) {
            val on = h.groupValues[1].equals("on", true)
            val v = battery.find(text)?.groupValues?.get(1)?.replace('.', ',')
            val l = left.find(text)?.groupValues?.get(1)?.toIntOrNull()
            val cycle = time.find(text)?.groupValues?.get(1)?.toIntOrNull()
            val volts = if (v != null) "АКБ $v В" else ""
            if (on && l != null && l > 0 && (cycle == null || l <= cycle)) {
                title = "$name · прогрев запущен"
                line = listOf("Осталось $l мин", volts).filter { it.isNotEmpty() }.joinToString(" · ")
                if (id.isNotEmpty()) Alerts.schedule(c, JSONObject().put("key", "timer_$id").put("car", id)
                    .put("name", rawName).put("at", System.currentTimeMillis() + l * 60_000L)
                    .put("daily", false).put("minutes", 0))
            } else {
                title = "$name · прогрев выключен"
                line = volts.ifEmpty { "Модуль ответил на запрос состояния." }
                if (id.isNotEmpty() && !on) Alerts.cancel(c, "timer_$id")
            }
        } else if (text.equals("OK", true) || text.equals("OK.", true)) {
            title = "$name · команда принята"
            line = "Модуль ответил OK."
        } else if (balanceHint.containsMatchIn(text)) {
            val m = amount.find(text) ?: afterHint.find(text)
            val v = m?.groupValues?.get(1)?.replace(',', '.')?.toDoubleOrNull()
            if (v != null && v < 50) {
                title = "$name · мало денег на SIM"
                line = "Баланс ${rub(v)}. Пополните SIM-карту модуля."
            } else if (v != null) {
                title = "$name · баланс ${rub(v)}"
                line = "Ответ модуля на запрос баланса."
            } else {
                title = "$name · баланс SIM"
                line = text.take(160)
            }
        } else {
            title = "$name · ответ модуля"
            line = text.take(160)
        }
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Ответы модуля", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Состояние прогрева, баланс и другие ответы модуля, когда приложение закрыто"
            })
        }
        if (Build.VERSION.SDK_INT >= 24 && !nm.areNotificationsEnabled()) return
        val target = Intent(c, MainActivity::class.java).setData(Uri.parse("larin://reply/$id"))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (id.isNotEmpty()) target.putExtra("car", id)
        val tap = PendingIntent.getActivity(c, 1, target, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CHANNEL) else Notification.Builder(c)
        val n = builder.setSmallIcon(R.drawable.notification_icon).setContentTitle(title).setContentText(line)
            .setStyle(Notification.BigTextStyle().bigText(line)).setAutoCancel(true).setContentIntent(tap)
            .setCategory(Notification.CATEGORY_STATUS).build()
        try { nm.notify("reply_$id", 2, n) } catch (_: SecurityException) { }
    }
}
