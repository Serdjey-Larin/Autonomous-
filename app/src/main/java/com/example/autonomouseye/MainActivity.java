package com.example.autonomouseye;

import android.Manifest;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Rect;
import android.graphics.RectF;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.face.Face;
import com.google.mlkit.vision.face.FaceDetection;
import com.google.mlkit.vision.face.FaceDetector;
import com.google.mlkit.vision.face.FaceDetectorOptions;

import org.videolan.libvlc.LibVLC;
import org.videolan.libvlc.Media;
import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.util.VLCVideoLayout;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class MainActivity extends AppCompatActivity {

    private static final String PREFS = "eye";
    private static final String PREF_URL = "rtsp_url";
    private static final String DEFAULT_URL =
            "rtsp://admin:123456@192.168.0.112:554/0/av1";

    // ====== НАСТРОЙКИ MQTT ======
    private static final String MQTT_BROKER =
            "ssl://o66f8ec6.ala.eu-central-1.emqxsl.com:8883";
    private static final String MQTT_USER = "Eye";
    private static final String MQTT_PASS = "Eye12345!";
    private static final String TOPIC_EVENT = "home/gate/event/face";
    private static final String TOPIC_STATUS = "home/gate/status";
    private static final String TOPIC_BATTERY = "home/gate/battery";

    private LibVLC libVLC;
    private MediaPlayer mediaPlayer;
    private VLCVideoLayout videoLayout;
    private OverlayView overlay;
    private EditText urlInput;
    private TextView statusText;
    private View statusDot;
    private TextView counterOverlay;
    private FaceDetector faceDetector;
    private SharedPreferences prefs;
    private MqttManager mqttManager;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean detectionRunning = false;
    private static final int DETECT_INTERVAL_MS = 1500;
    private String lastUrl = "";
    private long lastMqttPublish = 0;
    private static final long MQTT_COOLDOWN_MS = 10000;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        requestNotificationPermission();

        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);

        videoLayout = findViewById(R.id.video_layout);
        overlay = findViewById(R.id.overlay);
        urlInput = findViewById(R.id.url_input);
        statusText = findViewById(R.id.status_text);
        statusDot = findViewById(R.id.status_dot);
        counterOverlay = findViewById(R.id.counter_overlay);

        String savedUrl = prefs.getString(PREF_URL, DEFAULT_URL);
        urlInput.setText(savedUrl);

        FaceDetectorOptions faceOpts = new FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                .setMinFaceSize(0.1f)
                .build();
        faceDetector = FaceDetection.getClient(faceOpts);

        ArrayList<String> options = new ArrayList<>();
        options.add("--rtsp-tcp");
        options.add("--network-caching=1500");

        libVLC = new LibVLC(this, options);
        mediaPlayer = new MediaPlayer(libVLC);

        videoLayout.post(() -> {
            try {
                mediaPlayer.attachViews(videoLayout, null, false, true);
            } catch (Exception ignored) {}
        });

        mediaPlayer.setEventListener(event -> {
            if (event.type == MediaPlayer.Event.Playing) {
                if (!detectionRunning) startDetection();
            }
        });

        setStatus(false, "Отключено");
        updateCounterOverlay();

        Button playBtn = findViewById(R.id.play_btn);
        Button stopBtn = findViewById(R.id.stop_btn);
        Button detectBtn = findViewById(R.id.detect_btn);
        Button serviceBtn = findViewById(R.id.service_btn);
        Button statsBtn = findViewById(R.id.stats_btn);

        playBtn.setOnClickListener(v -> {
            String url = urlInput.getText().toString();
            prefs.edit().putString(PREF_URL, url).apply();
            playStream(url);
        });

        stopBtn.setOnClickListener(v -> {
            stopDetection();
            mediaPlayer.stop();
            overlay.clear();
            setStatus(false, "Остановлено");
            lastUrl = "";
        });

        detectBtn.setOnClickListener(v -> {
            if (detectionRunning) {
                stopDetection();
                overlay.clear();
                Toast.makeText(this, "Детектор выключен", Toast.LENGTH_SHORT).show();
            } else {
                startDetection();
            }
        });

        serviceBtn.setOnClickListener(v -> {
            String url = urlInput.getText().toString();
            prefs.edit().putString(PREF_URL, url).apply();
            startDetectorService(url);
        });

        statsBtn.setOnClickListener(v -> showStats());

        Button snapshotBtn = findViewById(R.id.snapshot_btn);
        if (snapshotBtn != null) {
            snapshotBtn.setOnClickListener(v -> takeEnhancedSnapshot());
        }

        // Инициализация MQTT
        initMqtt();

        // Автозапуск
        startDetectorService(savedUrl);
        handler.postDelayed(() -> playStream(savedUrl), 1500);
    }

    private void initMqtt() {
        try {
            mqttManager = new MqttManager(this, MQTT_BROKER);
            mqttManager.setListener(new MqttManager.MqttListener() {
                @Override
                public void onConnected() {
                    Log.d("MQTT", "Connected");
                    runOnUiThread(() -> Toast.makeText(MainActivity.this,
                            "MQTT подключён", Toast.LENGTH_SHORT).show());
                    mqttManager.subscribe(TOPIC_BATTERY, 1);
                    mqttManager.publish(TOPIC_STATUS, "online", 1, true);
                }

                @Override
                public void onDisconnected() {
                    Log.d("MQTT", "Disconnected");
                    runOnUiThread(() -> Toast.makeText(MainActivity.this,
                            "MQTT отключён", Toast.LENGTH_SHORT).show());
                }

                @Override
                public void onMessageReceived(String topic, String payload) {
                    Log.d("MQTT", topic + ": " + payload);
                    if (TOPIC_BATTERY.equals(topic)) {
                        runOnUiThread(() -> statusText.setText("АКБ: " + payload + " В"));
                    }
                }

                @Override
                public void onError(String error) {
                    Log.e("MQTT", error);
                }
            });
            mqttManager.connect(MQTT_USER, MQTT_PASS);
        } catch (Exception e) {
            Toast.makeText(this, "MQTT ошибка: " + e.getMessage(),
                    Toast.LENGTH_LONG).show();
        }
    }

    private void setStatus(boolean online, String text) {
        statusText.setText(text);
        statusDot.setBackgroundColor(ContextCompat.getColor(this,
                online ? R.color.success : R.color.error));
    }

    private void playStream(String url) {
        try {
            lastUrl = url;
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

    private void startDetection() {
        if (detectionRunning) return;
        detectionRunning = true;
        handler.post(detectionLoop);
    }

    private void stopDetection() {
        detectionRunning = false;
        handler.removeCallbacks(detectionLoop);
    }

    private final Runnable detectionLoop = new Runnable() {
        @Override
        public void run() {
            if (!detectionRunning) return;
            processFrame();
            handler.postDelayed(this, DETECT_INTERVAL_MS);
        }
    };

    private void processFrame() {
        Bitmap bitmap = captureFrame();
        if (bitmap == null) return;

        InputImage image = InputImage.fromBitmap(bitmap, 0);
        faceDetector.process(image)
                .addOnSuccessListener(faces -> {
                    List<RectF> boxes = new ArrayList<>();
                    float scaleX = (float) overlay.getWidth() / bitmap.getWidth();
                    float scaleY = (float) overlay.getHeight() / bitmap.getHeight();
                    for (Face face : faces) {
                        Rect b = face.getBoundingBox();
                        boxes.add(new RectF(
                                b.left * scaleX,
                                b.top * scaleY,
                                b.right * scaleX,
                                b.bottom * scaleY
                        ));
                    }
                    overlay.setBoxes(boxes);
                    if (!boxes.isEmpty()) {
                        statusText.setText("Лиц в кадре: " + boxes.size());

                        // Публикуем событие в MQTT (не чаще 1 раза в 10 сек)
                        long now = System.currentTimeMillis();
                        if (now - lastMqttPublish > MQTT_COOLDOWN_MS) {
                            lastMqttPublish = now;
                            publishFaceEvent(boxes.size());
                        }
                    }
                })
                .addOnFailureListener(e -> { });
    }

    private void publishFaceEvent(int count) {
        if (mqttManager == null || !mqttManager.isConnected()) return;
        String payload = "{\"count\":" + count
                + ",\"time\":\"" + new Date().toString() + "\"}";
        mqttManager.publish(TOPIC_EVENT, payload, 1, false);
        Log.d("MQTT", "Published: " + payload);
    }

    private Bitmap captureFrame() {
        try {
            int w = videoLayout.getWidth();
            int h = videoLayout.getHeight();
            if (w <= 0 || h <= 0) return null;
            Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(bmp);
            videoLayout.draw(canvas);
            return bmp;
        } catch (Exception e) {
            return null;
        }
    }

    private void takeEnhancedSnapshot() {
        Bitmap raw = captureFrame();
        if (raw == null) {
            Toast.makeText(this, "Кадр пуст — включите Play", Toast.LENGTH_SHORT).show();
            return;
        }

        Toast.makeText(this, "Обработка кадра...", Toast.LENGTH_SHORT).show();

        new Thread(() -> {
            Bitmap enhanced = ImageEnhancer.enhance(raw);
            try {
                File dir = new File(getExternalFilesDir(null), "events");
                if (!dir.exists()) dir.mkdirs();
                SimpleDateFormat sdf = new SimpleDateFormat(
                        "yyyy-MM-dd_HH-mm-ss", Locale.getDefault());
                String stamp = sdf.format(new Date());
                File out = new File(dir, "snap_" + stamp + ".jpg");
                FileOutputStream fos = new FileOutputStream(out);
                enhanced.compress(Bitmap.CompressFormat.JPEG, 92, fos);
                fos.flush();
                fos.close();

                runOnUiThread(() -> Toast.makeText(MainActivity.this,
                        "Сохранено: " + out.getName(),
                        Toast.LENGTH_LONG).show());
            } catch (Exception e) {
                runOnUiThread(() -> Toast.makeText(MainActivity.this,
                        "Ошибка: " + e.getMessage(),
                        Toast.LENGTH_LONG).show());
            }
        }).start();
    }

    private void startDetectorService(String url) {
        try {
            Intent intent = new Intent(this, DetectorService.class);
            intent.putExtra("rtsp_url", url);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent);
            } else {
                startService(intent);
            }
            setStatus(true, "Сервис работает в фоне");
        } catch (Exception e) {
            Toast.makeText(this, "Ошибка сервиса: " + e.getMessage(),
                    Toast.LENGTH_LONG).show();
        }
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
                    p[0] + "\nСегодня: " + p[1] + "\nВсего: " + p[2],
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
    protected void onStart() {
        super.onStart();
        if (mediaPlayer != null && videoLayout != null) {
            videoLayout.post(() -> {
                try {
                    mediaPlayer.detachViews();
                    mediaPlayer.attachViews(videoLayout, null, false, true);
                } catch (Exception ignored) {}
            });
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (mediaPlayer != null && mediaPlayer.getMedia() != null && !lastUrl.isEmpty()) {
            handler.postDelayed(() -> {
                try {
                    mediaPlayer.play();
                    setStatus(true, "Поток идёт");
                    if (!detectionRunning) startDetection();
                } catch (Exception ignored) {}
            }, 500);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (mediaPlayer != null) {
            try { mediaPlayer.detachViews(); } catch (Exception ignored) {}
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopDetection();
        if (mqttManager != null) mqttManager.disconnect();
        if (mediaPlayer != null) { mediaPlayer.stop(); mediaPlayer.release(); }
        if (libVLC != null) libVLC.release();
        if (faceDetector != null) faceDetector.close();
    }
}
