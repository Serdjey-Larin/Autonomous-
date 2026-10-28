package ru.larincold.larin_cold_gsm_control

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONArray
import org.json.JSONObject

internal fun normalizedSender(value: String): String {
    var digits = value.filter { it in '0'..'9' }
    if (digits.length == 11 && digits.startsWith("8")) digits = "7" + digits.drop(1)
    if (digits.startsWith("00")) digits = digits.drop(2)
    return digits
}

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val prefs = context.getSharedPreferences("larin_sms", Context.MODE_PRIVATE)
        val expected = prefs.getString("device", "") ?: ""
        if (expected.length < 10) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (parts.isEmpty() || parts.any { normalizedSender(it.originatingAddress ?: "") != expected }) return
        val body = parts.joinToString("") { it.messageBody ?: "" }
        if (body.isBlank()) return
        val receivedAt = System.currentTimeMillis()
        val sentAt = parts.first().timestampMillis
        val item = JSONObject().put("body", body).put("receivedAt", receivedAt).put("sentAt", sentAt)
        val old = try { JSONArray(prefs.getString("messages", "[]")) } catch (_: Exception) { JSONArray() }
        // Redelivered broadcasts must not create a new confirmation.
        for (i in 0 until old.length()) {
            val row = old.getJSONObject(i)
            if (row.optLong("sentAt") == sentAt && row.optString("body") == body) return
        }
        val buffer = JSONArray()
        for (i in maxOf(0, old.length() - 29) until old.length()) buffer.put(old.getJSONObject(i))
        buffer.put(item)
        // Synchronous, tiny write: preserve the reply before this receiver exits.
        prefs.edit().putString("messages", buffer.toString()).commit()
    }
}
