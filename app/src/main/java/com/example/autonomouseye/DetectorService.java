package com.example.autonomouseye;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.face.FaceDetection;
import com.google.mlkit.vision.face.FaceDetector;
import com.google.mlkit.vision.face.FaceDetectorOptions;

import org.videolan.libvlc.LibVLC;
import org.videolan.libvlc.Media;
import org.videolan.libvlc.MediaPlayer;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Locale;

public class DetectorService extends Service {

    private static final String CHANNEL_ID = "detector_service";
    private static final int NOTIFICATION_ID = 1;
    private static final int INTERVAL_MS = 5000;
    private static final long COOLDOWN_MS = 15000;

    private LibVLC libVLC;
    private MediaPlayer mediaPlayer;
    private FaceDetector faceDetector;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean running = false;
    private long lastSavedAt = 0L;
    private String rtspUrl = "rtsp://admin:123456@192.168.0.112:554/0/av1";
    private String cameraIp = "192.168.0.112";
    private String cameraUser = "admin";
    private String cameraPass = "123456";

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(NOTIFICATION_ID, buildNotification("AutonomousEye запущен"));

        ArrayList<String> options = new ArrayList<>();
        options.add("--rtsp-tcp");
        options.add("--network-caching=1500");
        options.add("--no-audio");
        options.add("--vout=dummy");

        libVLC = new LibVLC(this, options);
        mediaPlayer = new MediaPlayer(libVLC);

        FaceDetectorOptions faceOpts = new FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                .setMinFaceSize(0.1f)
                .build();
        faceDetector = FaceDetection.getClient(faceOpts);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && intent.hasExtra("rtsp_url")) {
            rtspUrl = intent.getStringExtra("rtsp_url");
            parseRtspUrl(rtspUrl);
        }
        if (!running) {
            running = true;
            playStream();
            handler.postDelayed(detectionLoop, 5000);
        }
        return START_STICKY;
    }

    private void parseRtspUrl(String url) {
        try {
            // rtsp://user:pass@IP:port/...
            String withoutScheme = url.replace("rtsp://", "");
            String creds = withoutScheme.substring(0, withoutScheme.indexOf('@'));
            String rest = withoutScheme.substring(withoutScheme.indexOf('@') + 1);
            cameraUser = creds.substring(0, creds.indexOf(':'));
            cameraPass = creds.substring(creds.indexOf(':') + 1);
            cameraIp = rest.substring(0, rest.indexOf(':'));
        } catch (Exception e) {
            // оставляем дефолтные значения
        }
    }

    private void playStream() {
        try {
            Media media = new Media(libVLC, android.net.Uri.parse(rtspUrl));
            mediaPlayer.setMedia(media);
            media.release();
            mediaPlayer.play();
            updateNotification("Камера: RTSP-соединение установлено");
        } catch (Exception e) {
            updateNotification("Ошибка RTSP: " + e.getMessage());
        }
    }

    private final Runnable detectionLoop = new Runnable() {
        @Override
        public void run() {
            if (!running) return;
            captureAndDetect();
            handler.postDelayed(this, INTERVAL_MS);
        }
    };

    private void captureAndDetect() {
        new Thread(() -> {
            Bitmap bitmap = fetchSnapshot();
            if (bitmap == null) {
                updateNotification("Снимок недоступен (проверьте snapshot URL)");
                return;
            }
            InputImage image = InputImage.fromBitmap(bitmap, 0);
            faceDetector.process(image)
                    .addOnSuccessListener(faces -> {
                        int count = faces.size();
                        if (count > 0) {
                            updateNotification("Лиц в кадре: " + count);
                            long now = System.currentTimeMillis();
                            if (now - lastSavedAt > COOLDOWN_MS) {
                                lastSavedAt = now;
                                saveEvent(bitmap, count);
                            }
                        } else {
                            updateNotification("Камера активна, лиц нет");
                        }
                    })
                    .addOnFailureListener(e -> { /* пропускаем кадр */ });
        }).start();
    }

    /** Пробуем несколько типовых HTTP-адресов снимков. */
    private Bitmap fetchSnapshot() {
        String[] urls = {
                "http://" + cameraUser + ":" + cameraPass + "@" + cameraIp + "/snapshot.jpg",
                "http://" + cameraUser + ":" + cameraPass + "@" + cameraIp + "/cgi-bin/snapshot.cgi",
                "http://" + cameraUser + ":" + cameraPass + "@" + cameraIp + "/tmpfs/auto.jpg",
                "http://" + cameraUser + ":" + cameraPass + "@" + cameraIp + "/snap.jpg",
                "http://" + cameraUser + ":" + cameraPass + "@" + cameraIp + ":8080/snapshot.jpg",
        };
        for (String u : urls) {
            Bitmap b = tryFetch(u);
            if (b != null) return b;
        }
        return null;
    }

    private Bitmap tryFetch(String urlStr) {
        HttpURLConnection conn = null;
        try {
            URL u = new URL(urlStr);
            conn = (HttpURLConnection) u.openConnection();
            conn.setConnectTimeout(2500);
            conn.setReadTimeout(2500);
            conn.setDoInput(true);
            conn.connect();
            if (conn.getResponseCode() == 200) {
                InputStream is = conn.getInputStream();
                Bitmap bmp = BitmapFactory.decodeStream(is);
                is.close();
                return bmp;
            }
        } catch (Exception e) {
            // пробуем следующий
        } finally {
            if (conn != null) conn.disconnect();
        }
        return null;
    }

    private void saveEvent(Bitmap bitmap, int faceCount) {
        try {
            File baseDir = new File(getExternalFilesDir(null), "events");
            if (!baseDir.exists()) baseDir.mkdirs();

            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.getDefault());
            String stamp = sdf.format(new Date());

            File photoFile = new File(baseDir, "face_" + stamp + ".jpg");
            FileOutputStream out = new FileOutputStream(photoFile);
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out);
            out.flush();
            out.close();

            File logFile = new File(baseDir, "log.txt");
            FileWriter fw = new FileWriter(logFile, true);
            fw.write(stamp + " | лиц: " + faceCount + " | " + photoFile.getName() + "\n");
            fw.close();

            showDetectionNotification(bitmap, faceCount);
        } catch (Exception e) {
            // игнорируем сбой записи
        }
    }

    private void showDetectionNotification(Bitmap preview, int count) {
        NotificationCompat.Builder builder =
                new NotificationCompat.Builder(this, CHANNEL_ID)
                        .setSmallIcon(android.R.drawable.ic_menu_camera)
                        .setContentTitle("Обнаружено лиц: " + count)
                        .setContentText("Нажмите, чтобы открыть приложение")
                        .setStyle(new NotificationCompat.BigPictureStyle().bigPicture(preview))
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setAutoCancel(true);

        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.notify((int) System.currentTimeMillis(), builder.build());
    }

    private Notification buildNotification(String text) {
        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentTitle("AutonomousEye")
                .setContentText(text)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build();
    }

    private void updateNotification(String text) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.notify(NOTIFICATION_ID, buildNotification(text));
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID,
                    "Детектор лиц",
                    NotificationManager.IMPORTANCE_LOW
            );
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(ch);
        }
    }

    @Override
    public void onDestroy() {
        running = false;
        handler.removeCallbacksAndMessages(null);
        if (mediaPlayer != null) {
            mediaPlayer.stop();
            mediaPlayer.release();
        }
        if (libVLC != null) libVLC.release();
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
