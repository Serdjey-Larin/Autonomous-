package ru.larincold.gsmprobe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootProbeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ProbeLog.processStart(context, "BOOT_COMPLETED")
        ProbeLog.write(context, "ЗАГРУЗКА", "получен ${intent.action} (приёмник exported=false)")
    }
}
