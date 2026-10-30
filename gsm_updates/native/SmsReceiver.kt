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
            if (n.isEmpty()) continue
            val row = JSONObject().put("number", n)
                .put("id", car["id"] as? String ?: "").put("name", car["name"] as? String ?: "")
                .put("duration", (car["duration"] as? Number)?.toInt() ?: 30)
            (car["pending"] as? String)?.let { row.put("pending", it) }
            (car["pendingSince"] as? Number)?.let { row.put("pendingSince", it.toLong()) }
            (car["cmdAt"] as? Number)?.let { row.put("cmdAt", it.toLong()) }
            (car["outAt"] as? Number)?.let { row.put("outAt", it.toLong()) }
            info.put(row)
        }
        synchronized(lock) {
            prefs(c).edit().putString("devices", set.joinToString("\n")).putString("cars", info.toString()).commit()
        }
    }

    /** Данные автомобиля по номеру модуля: id, название, ожидаемая команда. */
    fun car(c: Context, number: String): JSONObject? {
        synchronized(lock) {
            val rows = try { JSONArray(prefs(c).getString("cars", "[]")) } catch (_: Exception) { return null }
            for (i in 0 until rows.length()) {
                val r = rows.getJSONObject(i)
                if (r.optString("number") == number) return r
            }
            return null
        }
    }

    /** Принят STATUS в фоне: запомнить его время, чтобы более старый его не перебил. */
    fun setOutAt(c: Context, number: String, at: Long) {
        synchronized(lock) {
            val p = prefs(c)
            val rows = try { JSONArray(p.getString("cars", "[]")) } catch (_: Exception) { return }
            for (i in 0 until rows.length()) {
                val r = rows.getJSONObject(i)
                if (r.optString("number") == number) r.put("outAt", at)
            }
            p.edit().putString("cars", rows.toString()).commit()
        }
    }

    /** Ответ на ожидаемую команду получен в фоне — больше ею не считаем. */
    fun consumePending(c: Context, number: String) {
        synchronized(lock) {
            val p = prefs(c)
            val rows = try { JSONArray(p.getString("cars", "[]")) } catch (_: Exception) { return }
            for (i in 0 until rows.length()) {
                val r = rows.getJSONObject(i)
                if (r.optString("number") == number) { r.remove("pending"); r.remove("pendingSince") }
            }
            p.edit().putString("cars", rows.toString()).commit()
        }
    }

    /** Машина удалена или номер сменён: убрать из журнала всё с этого номера. */
    fun forget(c: Context, rawNumber: String) {
        val number = normalize(rawNumber)
        synchronized(lock) {
            val p = prefs(c)
            val rows = try { JSONArray(p.getString("inbox", "[]")) } catch (_: Exception) { JSONArray() }
            val keep = JSONArray()
            for (i in 0 until rows.length()) if (rows.getJSONObject(i).optString("number") != number) keep.put(rows.getJSONObject(i))
            p.edit().putString("inbox", keep.toString()).commit()
        }
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
            try { ReplyNotifier.handle(context, SmsInbox.normalize(sender), body,
                parts.first().timestampMillis, System.currentTimeMillis()) } catch (_: Exception) { }
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
    private val already = Regex("""\balready\b|уже""", RegexOption.IGNORE_CASE)
    private val heater = Regex("""heater\s*:\s*(on|off)""", RegexOption.IGNORE_CASE)
    private val left = Regex("""left\s*:\s*(\d{1,3})\s*min""", RegexOption.IGNORE_CASE)
    private val time = Regex("""time\s*:\s*(\d{1,3})\s*min""", RegexOption.IGNORE_CASE)
    private val ignored = Regex("""old command ignored""", RegexOption.IGNORE_CASE)
    private val battery = Regex("""battery\s*:\s*(\d{1,2}[.,]\d)\s*v""", RegexOption.IGNORE_CASE)
    private val balanceHint = Regex("""^USSD\s*:|balans|баланс|balance""", RegexOption.IGNORE_CASE)
    private val amount = Regex("""(-?\d+(?:[.,]\d{1,2})?)\s*(?:rub|rur|руб|р(?![а-яё])|₽)""", RegexOption.IGNORE_CASE)
    private val afterHint = Regex("""(?:balans|баланс|balance)[^\d-]{0,24}(-?\d+(?:[.,]\d{1,2})?)""", RegexOption.IGNORE_CASE)

    private fun rub(v: Double): String {
        val a = kotlin.math.abs(v)
        val t = if (a == Math.rint(a)) a.toLong().toString() else String.format(java.util.Locale.ROOT, "%.2f", a).replace('.', ',')
        return (if (v < 0) "−" else "") + t + " ₽"
    }

    /** Те же тексты отказов, что moduleErrorText в reply_parser.dart. */
    private fun errorText(body: String): String? {
        val t = body.trim().uppercase()
        return when {
            t == "DENIED" -> "Команда доступна только мастер-номеру."
            t.startsWith("ERROR TIME") -> "Время должно быть от 15 до 120 мин."
            t == "ERROR PHONE" -> "Неверный номер телефона."
            t == "ERROR MAX 3" -> "Уже записаны 3 дополнительных номера."
            t == "ERROR USSD CODE" -> "Неверный USSD-код."
            t == "UNKNOWN COMMAND" -> "Модуль не знает такой команды."
            t == "NO GSM NETWORK" -> "У модуля нет сети."
            t == "NOT FOUND" -> "Номера нет в модуле."
            t == "ALREADY EXISTS" -> "Номер уже записан в модуле."
            t == "USSD CODE NOT SET" -> "Не задан USSD-код баланса."
            t == "USSD BUSY" || t.startsWith("USSD BUSY/") -> "Модуль занят запросом баланса."
            t.startsWith("USSD ") && !t.startsWith("USSD:") && !t.startsWith("USSD MENU") -> "Оператор не ответил на запрос баланса."
            else -> null
        }
    }

    private const val SKEW = 20_000L
    private const val REPLY_WINDOW = 15 * 60_000L

    /**
     * Те же правила времени, что в vehicle_state.dart: время SMS — по часам
     * SMS-центра (задержанное SMS остаётся старым), кроме времени «из будущего».
     */
    fun handle(c: Context, number: String, body: String, smscTs: Long, receivedAt: Long) {
        val car = SmsInbox.car(c, number)
        val id = car?.optString("id") ?: ""
        val rawName = car?.optString("name") ?: ""
        val name = rawName.ifBlank { "Автомобиль" }
        val text = body.trim()
        val at = if (smscTs - receivedAt > 120_000L) receivedAt else smscTs
        val pending = car?.optString("pending")?.takeIf { it.isNotEmpty() }
        val pendingSince = if (car != null && car.has("pendingSince")) car.optLong("pendingSince") else null
        val cmdMark = if (car != null && car.has("cmdAt")) car.optLong("cmdAt") else pendingSince
        fun answers(since: Long?) = since != null && receivedAt >= since && at >= since - SKEW && at - since <= REPLY_WINDOW
        fun timerKey() = "timer_$id"
        fun scheduleEnd(endMs: Long) {
            if (id.isEmpty()) return
            if (endMs > System.currentTimeMillis()) Alerts.schedule(c, JSONObject().put("key", timerKey()).put("car", id)
                .put("name", rawName).put("at", endMs).put("daily", false).put("minutes", 0))
            else Alerts.cancel(c, timerKey())
        }
        val h = heater.find(text)
        val err = errorText(text)
        var title: String
        var line: String
        // Те же проверки формата, что parseReply в Dart: Left и Time обязательны,
        // Left не больше Time при ON, Time 1–240, напряжение 5–18 В.
        val l = left.find(text)?.groupValues?.get(1)?.toIntOrNull()
        val cycle = time.find(text)?.groupValues?.get(1)?.toIntOrNull()
        val vNum = battery.find(text)?.groupValues?.get(1)?.replace(',', '.')?.toDoubleOrNull()
        val validStatus = h != null && l != null && cycle != null && cycle in 1..240 &&
            (vNum == null || vNum in 5.0..18.0) && !(h.groupValues[1].equals("on", true) && l > cycle)
        if (validStatus) {
            val on = h!!.groupValues[1].equals("on", true)
            val leftMin = l ?: 0
            val v = battery.find(text)?.groupValues?.get(1)?.replace('.', ',')
            val volts = if (v != null) "АКБ $v В" else ""
            // Не новее уже принятого STATUS — задержанный старый ответ: ничего не меняем и не показываем.
            val outAt = if (car != null && car.has("outAt")) car.optLong("outAt") else null
            if (outAt != null && at <= outAt) return
            // STATUS, сформированный до последней команды, устарел для таймера.
            val stale = cmdMark != null && at < cmdMark - SKEW
            if (!stale) {
                SmsInbox.setOutAt(c, number, at)
                if (pending != null && answers(pendingSince)) SmsInbox.consumePending(c, number)
            }
            val oldCmd = ignored.containsMatchIn(text)
            if (on && leftMin > 0) {
                title = when {
                    oldCmd -> "$name · старая команда не выполнена"
                    already.containsMatchIn(text) -> "$name · прогрев уже идёт"
                    else -> "$name · прогрев запущен"
                }
                line = listOf("Осталось $leftMin мин", volts).filter { it.isNotEmpty() }.joinToString(" · ")
                if (!stale) scheduleEnd(at + leftMin * 60_000L)
            } else {
                title = when {
                    oldCmd -> "$name · старая команда не выполнена"
                    already.containsMatchIn(text) -> "$name · прогрев уже выключен"
                    else -> "$name · прогрев выключен"
                }
                line = listOf("Время прогрева $cycle мин", volts).filter { it.isNotEmpty() }.joinToString(" · ")
                if (!stale && !on && id.isNotEmpty()) Alerts.cancel(c, timerKey())
            }
        } else if (text.equals("OK", true) || text.equals("OK.", true)) {
            title = "$name · команда принята"
            line = "Модуль ответил OK."
            // Прошивка, отвечающая «OK»: ведём таймер по ожидаемой команде, как экран.
            if (pending != null && answers(pendingSince)) {
                SmsInbox.consumePending(c, number)
                val duration = car?.optInt("duration", 30) ?: 30
                when {
                    pending == "START" -> { title = "$name · прогрев запущен"; line = "Модуль принял запуск."
                        scheduleEnd(at + duration * 60_000L) }
                    pending == "STOP" -> { title = "$name · прогрев выключен"; line = "Модуль принял остановку."
                        if (id.isNotEmpty()) Alerts.cancel(c, timerKey()) }
                    pending.startsWith("TIME:") -> line = "Модуль принял время ${pending.substring(5)} мин."
                }
            }
        } else if (err != null) {
            title = "$name · команда отклонена"
            line = err
            if (pending != null && answers(pendingSince)) SmsInbox.consumePending(c, number)
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
