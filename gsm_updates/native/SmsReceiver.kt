package ru.larincold.larin_cold_gsm_control

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
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

    fun setDevices(c: Context, numbers: List<String>) {
        val set = numbers.map { normalize(it) }.filter { it.isNotEmpty() }.toSortedSet()
        prefs(c).edit().putString("devices", set.joinToString("\n")).commit()
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
        if (stored) SmsInbox.listener?.invoke()
    }
}
