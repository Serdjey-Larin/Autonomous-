package com.example.autonomouseye;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.labeling.ImageLabel;
import com.google.mlkit.vision.labeling.ImageLabeler;
import com.google.mlkit.vision.labeling.ImageLabeling;

import org.videolan.libvlc.LibVLC;
import org.videolan.libvlc.Media;
import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.util.VLCVideoLayout;

import java.io.File;
import java.util.ArrayList;

public class MainActivity extends AppCompatActivity {

    private LibVLC libVLC;
    private MediaPlayer mediaPlayer;
    private VLCVideoLayout videoLayout;
    private EditText urlInput;
    private ImageLabeler labeler;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean detectionRunning = false;
    private int snapshotCounter = 0;
    private static final int DETECTION_INTERVAL_MS = 10000; // каждые 10 сек

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        createNotificationChannel();
        requestNotificationPermission();

        ArrayList<String> options = new ArrayList<>();
        options.add("--rtsp-tcp");
        options.add("--network-caching=1500");

        libVLC = new LibVLC(this, options);
        mediaPlayer = new MediaPlayer(libVLC);

        labeler = ImageLabeling.getClient(ImageLabelerOptionsImpl.DEFAULT);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        TextView title = new TextView(this);
        title.setText("AutonomousEye — детектор");
        title.setTextSize(20);
        root.addView(title);

        urlInput = new EditText(this);
        urlInput.setText("rtsp://admin:123456@192.168.0.112:554/0/av1");
        root.addView(urlInput);

        Button playBtn = new Button(this);
        playBtn.setText("Воспроизвести");
        root.addView(playBtn);

        Button detectBtn = new Button(this);
        detectBtn.setText("Старт детектор");
        root.addView(detectBtn);

        Button stopBtn = new Button(this);
        stopBtn.setText("Стоп");
        root.addView(stopBtn);

        videoLayout = new VLCVideoLayout(this);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f);
        videoLayout.setLayoutParams(lp);
        root.addView(videoLayout);

        setContentView(root);

        mediaPlayer.attachViews(videoLayout, null, false, false);

        playBtn.setOnClickListener(v -> playStream(urlInput.getText().toString()));
        detectBtn.setOnClickListener(v -> startDetection());
        stopBtn.setOnClickListener(v -> {
            stopDetection();
            mediaPlayer.stop();
        });
    }

    private void playStream(String url) {
        try {
            Media media = new Media(libVLC, Uri.parse(url));
            media.setHWDecoderEnabled(true, false);
            mediaPlayer.setMedia(media);
            media.release();
            mediaPlayer.play();
        } catch (Exception e) {
            urlInput.setError(e.getMessage());
        }
    }

    private void startDetection() {
        if (detectionRunning) return;
        detectionRunning = true;
        Toast.makeText(this, "Детектор включён", Toast.LENGTH_SHORT).show();
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
            takeSnapshotAndDetect();
            handler.postDelayed(this, DETECTION_INTERVAL_MS);
        }
    };

    private void takeSnapshotAndDetect() {
        try {
            snapshotCounter++;
            File outFile = new File(getExternalFilesDir(null),
                    "snap_" + snapshotCounter + ".png");
            String path = outFile.getAbsolutePath();

            boolean queued = mediaPlayer.takeSnapshot(0, path);
            if (!queued) return;

            // Ждём 800 мс, пока libVLC сохранит PNG
            handler.postDelayed(() -> analyzeSnapshot(outFile), 800);
        } catch (Exception e) {
            // игнорируем сбои одного кадра
        }
    }

    private void analyzeSnapshot(File file) {
        if (!file.exists() || file.length() == 0) return;

        Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath());
        if (bitmap == null) return;

        InputImage image = InputImage.fromBitmap(bitmap, 0);
        labeler.process(image)
                .addOnSuccessListener(labels -> {
                    boolean personFound = false;
                    float maxConf = 0f;
                    for (ImageLabel label : labels) {
                        if ("Person".equalsIgnoreCase(label.getText())
                                && label.getConfidence() > 0.7f) {
                            personFound = true;
                            maxConf = label.getConfidence();
                            break;
                        }
                    }
                    if (personFound) {
                        showDetectionNotification(file, maxConf);
                    }
                })
                .addOnFailureListener(e -> { /* пропускаем кадр */ });
    }

    private void showDetectionNotification(File photo, float confidence) {
        Bitmap preview = BitmapFactory.decodeFile(photo.getAbsolutePath());

        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, "detect_channel")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentTitle("Обнаружен человек!")
                .setContentText("Уверенность: " + Math.round(confidence * 100) + "%")
                .setStyle(new NotificationCompat.BigPictureStyle()
                        .bigPicture(preview))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true);

        NotificationManagerCompat.from(this).notify((int) System.currentTimeMillis(), builder.build());
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    "detect_channel",
                    "Детекция объектов",
                    NotificationManager.IMPORTANCE_HIGH
            );
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(channel);
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
    protected void onStop() {
        super.onStop();
        if (mediaPlayer != null) mediaPlayer.pause();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopDetection();
        if (mediaPlayer != null) {
            mediaPlayer.stop();
            mediaPlayer.release();
        }
        if (libVLC != null) libVLC.release();
    }
}
