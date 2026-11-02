package ru.larincold.gsmprobe

import android.content.Context
import android.os.Process
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Журнал диагностики. Хранится только на телефоне (files/probe.log), никуда не
 * отправляется. Записи разделяются символом RS, чтобы многострочные SMS не
 * разваливались при выводе «новые сверху».
 */
object ProbeLog {
    private const val SEP = '\u001E'
    private const val MAX_BYTES = 400_000L
    private const val PREFS = "probe"
    private val lock = Any()

    @Volatile var activityVisible = false
    @Volatile private var processLogged = false

    fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun file(c: Context) = File(c.filesDir, "probe.log")

    fun time(ms: Long): String =
        SimpleDateFormat("dd.MM HH:mm:ss", Locale.US).format(Date(ms))

    /** Однократная отметка о запуске процесса — видно, был ли процесс убит до SMS. */
    fun processStart(c: Context, who: String) {
        if (processLogged) return
        processLogged = true
        write(c, "ПРОЦЕСС", "процесс запущен (pid ${Process.myPid()}) из: $who")
    }

    fun write(c: Context, tag: String, text: String) {
        val entry = "${time(System.currentTimeMillis())}  [$tag]  $text"
        synchronized(lock) {
            val f = file(c.applicationContext)
            if (f.exists() && f.length() > MAX_BYTES) {
                // Оставляем последнюю половину журнала.
                val keep = f.readText().takeLast((MAX_BYTES / 2).toInt())
                f.writeText(keep.substringAfter(SEP, keep))
            }
            f.appendText(entry + SEP)
        }
    }

    fun entriesNewestFirst(c: Context): List<String> = synchronized(lock) {
        val f = file(c.applicationContext)
        if (!f.exists()) emptyList()
        else f.readText().split(SEP).filter { it.isNotBlank() }.reversed()
    }

    fun clear(c: Context) = synchronized(lock) { file(c.applicationContext).delete(); Unit }

    fun counter(c: Context, key: String): Int = prefs(c).getInt(key, 0)
    fun inc(c: Context, key: String) {
        val p = prefs(c)
        p.edit().putInt(key, p.getInt(key, 0) + 1).commit()
    }

    fun moduleNumber(c: Context): String = prefs(c).getString("module", "") ?: ""
    fun setModuleNumber(c: Context, value: String) {
        prefs(c).edit().putString("module", normalize(value)).commit()
    }

    /**
     * Нормализация в +E.164 для российских номеров (8XXXXXXXXXX → +7XXXXXXXXXX).
     * Остальные номера — «+» и цифры как есть. Сравнение — только полное равенство.
     */
    fun normalize(raw: String): String {
        var d = raw.filter { it in '0'..'9' }
        if (d.startsWith("00")) d = d.drop(2)
        if (d.length == 11 && d.startsWith("8")) d = "7" + d.drop(1)
        if (d.length == 10 && d.startsWith("9")) d = "7$d"
        return if (d.isEmpty()) "" else "+$d"
    }

    /** Чужой номер в журнал не пишем: только формат, длину и две последние цифры. */
    fun mask(raw: String): String {
        val d = raw.filter { it in '0'..'9' }
        if (d.length < 5) return "буквенный отправитель (${raw.length} символов)"
        val prefix = raw.takeWhile { !it.isDigit() } + d.take(1)
        return "$prefix${"•".repeat((d.length - 3).coerceAtLeast(0))}${d.takeLast(2)} (${d.length} цифр)"
    }

    /** Защита от повторной обработки одного и того же события. */
    fun seenBefore(c: Context, setKey: String, key: String): Boolean {
        val p = prefs(c)
        val list = (p.getString(setKey, "") ?: "").split('\n').filter { it.isNotEmpty() }
        if (key in list) return true
        val updated = (list + key).takeLast(200).joinToString("\n")
        p.edit().putString(setKey, updated).commit()
        return false
    }
}
