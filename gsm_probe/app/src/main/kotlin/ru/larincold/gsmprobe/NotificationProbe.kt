package ru.larincold.gsmprobe

import android.app.Notification
import android.app.Person
import android.content.ComponentName
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Вариант A: чтение уведомлений SMS-приложений. Уведомления остальных
 * приложений только считаются — их содержимое не читается и не сохраняется.
 */
class NotificationProbe : NotificationListenerService() {

    private val knownSmsApps = setOf(
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging",
        "com.android.messaging",
        "com.android.mms",
    )

    override fun onListenerConnected() {
        ProbeLog.processStart(this, "NotificationListener")
        ProbeLog.prefs(this).edit().putLong("nls_connected", System.currentTimeMillis()).commit()
        ProbeLog.write(this, "УВЕДОМЛ.", "служба уведомлений ПОДКЛЮЧЕНА системой")
    }

    override fun onListenerDisconnected() {
        ProbeLog.prefs(this).edit().putLong("nls_connected", 0L).commit()
        ProbeLog.write(this, "УВЕДОМЛ.", "служба уведомлений ОТКЛЮЧЕНА — запрашиваю переподключение")
        requestRebind(ComponentName(this, NotificationProbe::class.java))
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        ProbeLog.inc(this, "nls_total")
        val pkg = sbn.packageName
        val defaultSms = Telephony.Sms.getDefaultSmsPackage(this)
        if (pkg !in knownSmsApps && pkg != defaultSms) return
        ProbeLog.inc(this, "nls_sms_app")

        val n = sbn.notification
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val convTitle = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString() ?: ""
        val messages = readMessages(extras)
        val expected = ProbeLog.moduleNumber(this)

        fun looksLikeModule(s: String) = s.contains("LARIN", true) || s.contains("Heater", true) ||
            s.trim().equals("OK", true)
        fun hasModuleNumber(s: String?) = !s.isNullOrEmpty() && expected.isNotEmpty() &&
            ProbeLog.normalize(s) == expected

        val relevant = looksLikeModule(text) || looksLikeModule(bigText) ||
            messages.any { looksLikeModule(it.text) || hasModuleNumber(it.personUri) || hasModuleNumber(it.sender) } ||
            hasModuleNumber(title)
        val summary = n.flags and Notification.FLAG_GROUP_SUMMARY != 0

        if (!relevant) {
            ProbeLog.write(this, "УВЕДОМЛ.",
                "$pkg: уведомление не похоже на модуль (сообщений: ${messages.size}${if (summary) ", групповое" else ""}) — содержимое не сохраняется")
            return
        }

        val sb = StringBuilder()
        sb.append("пакет: $pkg").append(if (pkg == defaultSms) " (SMS по умолчанию)" else "")
        sb.append("\nkey: ${sbn.key}; id: ${sbn.id}; postTime: ${ProbeLog.time(sbn.postTime)}")
        sb.append("; групповое: ${if (summary) "да" else "нет"}; категория: ${n.category}")
        if (Build.VERSION.SDK_INT >= 29) sb.append("; shortcutId: ${n.shortcutId}")
        sb.append("\nзаголовок: '$title'; беседа: '$convTitle'")
        sb.append("\nEXTRA_TEXT: '$text'")
        if (bigText.isNotEmpty() && bigText != text) sb.append("\nEXTRA_BIG_TEXT: '$bigText'")
        sb.append("\nMessagingStyle: сообщений ${messages.size}")
        for ((i, m) in messages.withIndex()) {
            val key = "${sbn.key}|${m.time}|${m.text.hashCode()}"
            val repeat = ProbeLog.seenBefore(this, "nls_seen", key)
            sb.append("\n  #${i + 1} ${if (repeat) "(уже было)" else "НОВОЕ"} время ${ProbeLog.time(m.time)}")
            sb.append("\n     отправитель: имя='${m.sender ?: ""}' uri='${m.personUri ?: ""}' key='${m.personKey ?: ""}'")
            val uriMatch = hasModuleNumber(m.personUri)
            sb.append("\n     номер модуля в uri: ${if (uriMatch) "ДА" else "нет"}")
            sb.append("\n     текст:\n${m.text}")
        }
        ProbeLog.write(this, "УВЕДОМЛ. МОДУЛЬ?", sb.toString())
    }

    private data class Msg(val text: String, val time: Long, val sender: String?, val personUri: String?, val personKey: String?)

    @Suppress("DEPRECATION")
    private fun readMessages(extras: Bundle): List<Msg> {
        val arr: Array<Parcelable> = extras.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return emptyList()
        return arr.mapNotNull { p ->
            val b = p as? Bundle ?: return@mapNotNull null
            var name: String? = b.getCharSequence("sender")?.toString()
            var uri: String? = null
            var key: String? = null
            if (Build.VERSION.SDK_INT >= 28) {
                val person = b.getParcelable<Person>("sender_person")
                if (person != null) {
                    name = person.name?.toString() ?: name
                    uri = person.uri
                    key = person.key
                }
            }
            Msg(b.getCharSequence("text")?.toString() ?: "", b.getLong("time"), name, uri, key)
        }
    }
}
