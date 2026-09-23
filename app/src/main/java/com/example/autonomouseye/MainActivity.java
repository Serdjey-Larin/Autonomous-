package com.example.autonomouseye;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

public class MainActivity extends AppCompatActivity {

    private EditText urlInput;
    private TextView statusText;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        requestNotificationPermission();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        TextView title = new TextView(this);
        title.setText("AutonomousEye — пульт управления");
        title.setTextSize(20);
        root.addView(title);

        urlInput = new EditText(this);
        urlInput.setText("rtsp://admin:123456@192.168.0.112:554/0/av1");
        root.addView(urlInput);

        Button startBtn = new Button(this);
        startBtn.setText("Запустить сервис (фон)");
        root.addView(startBtn);

        Button stopBtn = new Button(this);
        stopBtn.setText("Остановить сервис");
        root.addView(stopBtn);

        Button pathBtn = new Button(this);
        pathBtn.setText("Где фото и лог?");
        root.addView(pathBtn);

        statusText = new TextView(this);
        statusText.setText("Статус: сервис остановлен");
        statusText.setTextSize(16);
        statusText.setPadding(0, 32, 0, 0);
        root.addView(statusText);

        setContentView(root);

        startBtn.setOnClickListener(v -> {
            Intent intent = new Intent(this, DetectorService.class);
            intent.putExtra("rtsp_url", urlInput.getText().toString());
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent);
            } else {
                startService(intent);
            }
            statusText.setText("Статус: сервис запущен (можно свернуть)");
            Toast.makeText(this, "Сервис запущен. Приложение можно закрыть.",
                    Toast.LENGTH_LONG).show();
        });

        stopBtn.setOnClickListener(v -> {
            stopService(new Intent(this, DetectorService.class));
            statusText.setText("Статус: сервис остановлен");
        });

        pathBtn.setOnClickListener(v -> {
            String path = getExternalFilesDir(null) + "/events";
            Toast.makeText(this, "Папка: " + path, Toast.LENGTH_LONG).show();
        });
    }

    private void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this,
                        new String[]{Manifest.permission.POST_NOTIFICATIONS}, 100);
            }
        }
    }
}
