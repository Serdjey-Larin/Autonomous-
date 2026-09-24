package com.example.autonomouseye;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

public class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;

        SharedPreferences prefs = context.getSharedPreferences("eye", Context.MODE_PRIVATE);
        String url = prefs.getString("rtsp_url",
                "rtsp://admin:123456@192.168.0.112:554/0/av1");

        Intent svc = new Intent(context, DetectorService.class);
        svc.putExtra("rtsp_url", url);

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(svc);
            } else {
                context.startService(svc);
            }
        } catch (Exception ignored) {
            // Android 12+ может запретить старт из фона — тогда юзер откроет приложение вручную
        }
    }
}
