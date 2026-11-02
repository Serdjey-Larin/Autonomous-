package ru.larincold.gsmprobe

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.Telephony
import android.text.InputType
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/**
 * Один экран: настройка номера модуля, состояние разрешений, кнопки перехода
 * в системные настройки и журнал событий (новые сверху).
 */
class MainActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var log: TextView
    private val handler = Handler(Looper.getMainLooper())
    private val refresher = object : Runnable {
        override fun run() { refresh(); handler.postDelayed(this, 2000) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ProbeLog.processStart(this, "экран приложения")
        title = "LARIN GSM · диагностика"

        val dp = resources.displayMetrics.density
        val pad = (16 * dp).toInt()
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(pad, pad, pad, pad) }
        val scroll = ScrollView(this).apply { addView(root) }
        scroll.setOnApplyWindowInsetsListener { v, insets ->
            val (top, bottom) = if (Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                bars.top to bars.bottom
            } else {
                @Suppress("DEPRECATION")
                insets.systemWindowInsetTop to insets.systemWindowInsetBottom
            }
            v.setPadding(0, top, 0, bottom)
            insets
        }
        setContentView(scroll)

        fun label(text: String, size: Float = 14f, bold: Boolean = false) = TextView(this).apply {
            this.text = text; textSize = size
            if (bold) setTypeface(typeface, Typeface.BOLD)
            setPadding(0, (8 * dp).toInt(), 0, (4 * dp).toInt())
        }
        fun button(text: String, action: () -> Unit) = Button(this).apply {
            this.text = text; isAllCaps = false; setOnClickListener { action() }
        }

        root.addView(label("Номер SIM-карты модуля (полностью, +7…)", bold = true))
        val number = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_PHONE
            setText(ProbeLog.moduleNumber(this@MainActivity))
            hint = "+79991234567"
        }
        root.addView(number)
        root.addView(button("Сохранить номер модуля") {
            val norm = ProbeLog.normalize(number.text.toString())
            if (norm.length < 11) { toast("Нужен полный номер, например +79991234567"); return@button }
            ProbeLog.setModuleNumber(this, norm)
            number.setText(norm)
            ProbeLog.write(this, "НАСТРОЙКА", "номер модуля: $norm")
            refresh()
        })

        root.addView(label("Состояние", bold = true))
        status = TextView(this).apply { textSize = 13f; setTextIsSelectable(true) }
        root.addView(status)

        root.addView(label("Доступ", bold = true))
        root.addView(button("1. Запросить разрешение на SMS") { requestSms() })
        root.addView(button("2. Сведения о приложении (⋮ → Разрешить ограниченные настройки)") {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
            ProbeLog.write(this, "ДЕЙСТВИЕ", "открыты «Сведения о приложении»")
        })
        root.addView(button("3. Доступ к уведомлениям") {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            ProbeLog.write(this, "ДЕЙСТВИЕ", "открыт «Доступ к уведомлениям»")
        })

        root.addView(label("Отметка в журнале (номер теста, что сейчас делаете)", bold = true))
        val note = EditText(this).apply { hint = "Тест 8: приложение смахнуто, жду STATUS" }
        root.addView(note)
        root.addView(button("Записать отметку") {
            val t = note.text.toString().trim()
            if (t.isNotEmpty()) { ProbeLog.write(this, "ОТМЕТКА", t); note.setText(""); refresh() }
        })

        root.addView(label("Журнал", bold = true))
        root.addView(button("Поделиться журналом") { shareLog() })
        root.addView(button("Очистить журнал и счётчики") {
            ProbeLog.clear(this)
            ProbeLog.prefs(this).edit().remove("sms_total").remove("sms_module")
                .remove("nls_total").remove("nls_sms_app").commit()
            ProbeLog.write(this, "ЖУРНАЛ", "очищен")
            refresh()
        })
        log = TextView(this).apply {
            textSize = 12f; typeface = Typeface.MONOSPACE; setTextIsSelectable(true)
            setPadding(0, (8 * dp).toInt(), 0, 0)
        }
        root.addView(log)
        root.addView(View(this).apply { minimumHeight = (40 * dp).toInt() })
    }

    override fun onResume() {
        super.onResume()
        ProbeLog.activityVisible = true
        handler.post(refresher)
    }

    override fun onPause() {
        ProbeLog.activityVisible = false
        handler.removeCallbacks(refresher)
        super.onPause()
    }

    private fun smsGranted() = checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    private fun requestSms() {
        ProbeLog.write(this, "ДЕЙСТВИЕ", "запрос RECEIVE_SMS (сейчас: ${if (smsGranted()) "разрешено" else "не разрешено"})")
        requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), 7)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 7) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        val rationale = shouldShowRequestPermissionRationale(Manifest.permission.RECEIVE_SMS)
        ProbeLog.write(this, "РАЗРЕШЕНИЕ",
            "RECEIVE_SMS: ${if (granted) "ВЫДАНО" else "НЕ выдано"}; " +
                "результатов: ${grantResults.size}; повторный запрос возможен: ${if (rationale) "да" else "нет"}")
        refresh()
    }

    private fun installSource(): String {
        val pm = packageManager
        return try {
            if (Build.VERSION.SDK_INT >= 30) {
                val info = pm.getInstallSourceInfo(packageName)
                val source = if (Build.VERSION.SDK_INT >= 33) when (info.packageSource) {
                    1 -> "другое"; 2 -> "магазин"; 3 -> "локальный файл"; 4 -> "скачанный файл"; else -> "не указан"
                } else "—"
                "установщик=${info.installingPackageName}; инициатор=${info.initiatingPackageName}; " +
                    "источник=${info.originatingPackageName}; тип=$source"
            } else {
                @Suppress("DEPRECATION")
                "установщик=${pm.getInstallerPackageName(packageName)}"
            }
        } catch (e: Exception) { "не удалось: ${e.javaClass.simpleName}" }
    }

    private fun restrictedAllowlist(): String = try {
        @Suppress("DEPRECATION")
        val list = packageManager.getWhitelistedRestrictedPermissions(
            packageName, PackageManager.FLAG_PERMISSION_WHITELIST_INSTALLER)
        if (Manifest.permission.RECEIVE_SMS in list) "RECEIVE_SMS в allowlist установщика: ДА"
        else "RECEIVE_SMS в allowlist установщика: НЕТ (${list.size} шт.)"
    } catch (e: SecurityException) {
        "allowlist установщика: системой не раскрывается"
    } catch (e: Exception) {
        "allowlist: ${e.javaClass.simpleName}"
    }

    private fun refresh() {
        val nm = getSystemService(NotificationManager::class.java)
        val nlsGranted = nm.isNotificationListenerAccessGranted(ComponentName(this, NotificationProbe::class.java))
        val connectedAt = ProbeLog.prefs(this).getLong("nls_connected", 0L)
        val version = try { packageManager.getPackageInfo(packageName, 0).versionName } catch (_: Exception) { "?" }
        val module = ProbeLog.moduleNumber(this)
        status.text = buildString {
            append("Телефон: ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})\n")
            append("Проба: $version\n")
            append("Установка: ${installSource()}\n")
            append("Номер модуля: ${if (module.isEmpty()) "НЕ ЗАДАН" else module}\n")
            append("SMS-приложение по умолчанию: ${Telephony.Sms.getDefaultSmsPackage(this@MainActivity)}\n")
            append("\nB · RECEIVE_SMS: ${if (smsGranted()) "РАЗРЕШЕНО ✓" else "не разрешено ✗"}\n")
            append("   ${restrictedAllowlist()}\n")
            append("   SMS всего: ${ProbeLog.counter(this@MainActivity, "sms_total")}, от модуля: ${ProbeLog.counter(this@MainActivity, "sms_module")}\n")
            append("\nA · Доступ к уведомлениям: ${if (nlsGranted) "ВКЛЮЧЁН ✓" else "выключен ✗"}\n")
            append("   служба: ${if (connectedAt > 0) "подключена с ${ProbeLog.time(connectedAt)}" else "не подключена"}\n")
            append("   уведомлений всего: ${ProbeLog.counter(this@MainActivity, "nls_total")}, от SMS-приложений: ${ProbeLog.counter(this@MainActivity, "nls_sms_app")}")
        }
        log.text = ProbeLog.entriesNewestFirst(this).take(150).joinToString("\n\n")
    }

    private fun shareLog() {
        val text = buildString {
            append(status.text).append("\n\n==== ЖУРНАЛ (новые сверху) ====\n\n")
            append(ProbeLog.entriesNewestFirst(this@MainActivity).joinToString("\n\n"))
        }.takeLast(90_000)
        val send = Intent(Intent.ACTION_SEND).setType("text/plain")
            .putExtra(Intent.EXTRA_SUBJECT, "LARIN GSM — журнал диагностики")
            .putExtra(Intent.EXTRA_TEXT, text)
        startActivity(Intent.createChooser(send, "Поделиться журналом"))
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_LONG).show()
}
