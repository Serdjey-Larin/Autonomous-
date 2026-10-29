package ru.larincold.gsmprobe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Вариант B: прямой приём новых SMS. Ничего не блокирует — Google Сообщения
 * и другие SMS-приложения получают сообщение как обычно.
 */
class SmsProbeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        ProbeLog.processStart(context, "SMS_RECEIVED")
        val receivedAt = System.currentTimeMillis()
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (parts.isNullOrEmpty()) {
            ProbeLog.write(context, "SMS", "событие без сообщений")
            return
        }
        ProbeLog.inc(context, "sms_total")
        val raw = parts.first().originatingAddress ?: ""
        val sameSender = parts.all { (it.originatingAddress ?: "") == raw }
        val body = parts.joinToString("") { it.messageBody ?: "" }
        val smscTs = parts.first().timestampMillis
        val norm = ProbeLog.normalize(raw)
        val expected = ProbeLog.moduleNumber(context)
        val match = expected.isNotEmpty() && norm == expected
        val app = if (ProbeLog.activityVisible) "приложение на экране" else "приложение НЕ на экране"

        if (!match) {
            val looksLikeModule = body.contains("LARIN", ignoreCase = true) ||
                body.contains("Heater", ignoreCase = true) || body.trim().equals("OK", ignoreCase = true)
            if (looksLikeModule) {
                ProbeLog.write(context, "SMS ⚠",
                    "текст похож на ответ модуля, но номер НЕ совпал: ${ProbeLog.mask(raw)}; " +
                        "ожидался ${if (expected.isEmpty()) "(номер модуля не задан)" else ProbeLog.mask(expected)}. " +
                        "Текст не сохраняется.")
            } else {
                ProbeLog.write(context, "SMS", "сообщение с другого номера ${ProbeLog.mask(raw)} — пропущено")
            }
            return
        }

        val dupKey = "$norm|$smscTs|${body.hashCode()}"
        val repeat = ProbeLog.seenBefore(context, "sms_seen", dupKey)
        if (!repeat) ProbeLog.inc(context, "sms_module")
        val delaySec = (receivedAt - smscTs) / 1000
        ProbeLog.write(context, if (repeat) "SMS ПОВТОР" else "SMS МОДУЛЯ ✓",
            "номер как пришёл: '$raw' → $norm; частей: ${parts.size}" +
                (if (sameSender) "" else " (РАЗНЫЕ отправители в частях!)") +
                "; время SMS-центра: ${ProbeLog.time(smscTs)}; задержка ≈ ${delaySec} с; $app\n$body")
    }
}
