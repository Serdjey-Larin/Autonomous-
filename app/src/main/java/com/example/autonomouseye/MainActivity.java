package com.example.autonomouseye;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import org.videolan.libvlc.LibVLC;
import org.videolan.libvlc.Media;
import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.util.VLCVideoLayout;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.util.ArrayList;

public class MainActivity extends AppCompatActivity {

    private LibVLC libVLC;
    private MediaPlayer mediaPlayer;
    private VLCVideoLayout videoLayout;
    private OverlayView overlay;
    private EditText urlInput;
    private TextView statusText;
    private View statusDot;
    private TextView counterOverlay;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        requestNotificationPermission();

        videoLayout = findViewById(R.id.video_layout);
        overlay = findViewById(R.id.overlay);
        urlInput = findViewById(R.id.url_input);
        statusText = findViewById(R.id.status_text);
        statusDot = findViewById(R.id.status_dot);
        counterOverlay = findViewById(R.id.counter_overlay);

        urlInput.setText("rtsp://admin:123456@192.168.0.112:554/0/av1");

        ArrayList<String> options = new ArrayList<>();
        options.add("--rtsp-tcp");
        options.add("--network-caching=1500");

        libVLC = new LibVLC(this, options);
        mediaPlayer = new MediaPlayer(libVLC);
        mediaPlayer.attachViews(videoLayout, null, false, false);

        setStatus(false, "Отключено");
        updateCounterOverlay();

        Button playBtn = findViewById(R.id.play_btn);
        Button stopBtn = findViewById(R.id.stop_btn);
        Button detectBtn = findViewById(R.id.detect_btn);
        Button serviceBtn = findViewById(R.id.service_btn);
        Button statsBtn = findViewById(R.id.stats_btn);

        playBtn.setOnClickListener(v -> playStream(urlInput.getText().toString()));

        stopBtn.setOnClickListener(v -> {
            mediaPlayer.stop();
            overlay.clear();
            setStatus(false, "Остановлено");
        });

        detectBtn.setOnClickListener(v -> Toast.makeText(this,
                "Для фоновой детекции нажмите «Сервис»",
                Toast.LENGTH_LONG).show());

        serviceBtn.setOnClickListener(v -> startDetectorService());
        statsBtn.setOnClickListener(v -> showStats());
    }

    private void setStatus(boolean online, String text) {
        statusText.setText(text);
        statusDot.setBackgroundColor(ContextCompat.getColor(this,
                online ? R.color.success : R.color.error));
    }

    private void playStream(String url) {
        try {
            Media media = new Media(libVLC, Uri.parse(url));
            media.setHWDecoderEnabled(true, false);
            mediaPlayer.setMedia(media);
            media.release();
            mediaPlayer.play();
            setStatus(true, "Поток идёт");
        } catch (Exception e) {
            urlInput.setError(e.getMessage());
            setStatus(false, "Ошибка: " + e.getMessage());
        }
    }

    private void startDetectorService() {
        Intent intent = new Intent(this, DetectorService.class);
        intent.putExtra("rtsp_url", urlInput.getText().toString());
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent);
        } else {
            startService(intent);
        }
        Toast.makeText(this, "Сервис запущен. Приложение можно закрыть.",
                Toast.LENGTH_LONG).show();
        setStatus(true, "Сервис работает в фоне");
    }

    private void updateCounterOverlay() {
        try {
            File f = new File(getExternalFilesDir(null), "counters.txt");
            if (!f.exists()) {
                counterOverlay.setText("");
                return;
            }
            BufferedReader br = new BufferedReader(new FileReader(f));
            String line = br.readLine();
            br.close();
            String[] p = line.split("\\|");
            counterOverlay.setText("Сегодня: " + p[1] + "  |  Всего: " + p[2]);
        } catch (Exception e) {
            counterOverlay.setText("");
        }
    }

    private void showStats() {
        try {
            File f = new File(getExternalFilesDir(null), "counters.txt");
            if (!f.exists()) {
                Toast.makeText(this, "Статистики пока нет", Toast.LENGTH_SHORT).show();
                return;
            }
            BufferedReader br = new BufferedReader(new FileReader(f));
            String line = br.readLine();
            br.close();
            String[] p = line.split("\\|");
            Toast.makeText(this,
                    "📅 " + p[0] + "\nСегодня: " + p[1] + "\nВсего: " + p[2],
                    Toast.LENGTH_LONG).show();
            updateCounterOverlay();
        } catch (Exception e) {
            Toast.makeText(this, "Ошибка: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
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

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (mediaPlayer != null) {
            mediaPlayer.stop();
            mediaPlayer.release();
        }
        if (libVLC != null) libVLC.release();
    }
}
