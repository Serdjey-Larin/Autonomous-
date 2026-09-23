package com.example.autonomouseye;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Rect;
import android.graphics.RectF;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.face.Face;
import com.google.mlkit.vision.face.FaceDetection;
import com.google.mlkit.vision.face.FaceDetector;
import com.google.mlkit.vision.face.FaceDetectorOptions;

import org.videolan.libvlc.LibVLC;
import org.videolan.libvlc.Media;
import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.util.VLCVideoLayout;

import java.util.ArrayList;
import java.util.List;

public class MainActivity extends AppCompatActivity {

    private LibVLC libVLC;
    private MediaPlayer mediaPlayer;
    private VLCVideoLayout videoLayout;
    private OverlayView overlay;
    private EditText urlInput;
    private FaceDetector faceDetector;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean detectionRunning = false;
    private static final int INTERVAL_MS = 1500; // каждые 1.5 сек

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ArrayList<String> options = new ArrayList<>();
        options.add("--rtsp-tcp");
        options.add("--network-caching=1500");

        libVLC = new LibVLC(this, options);
        mediaPlayer = new MediaPlayer(libVLC);

        FaceDetectorOptions faceOpts = new FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                .setMinFaceSize(0.1f)
                .build();
        faceDetector = FaceDetection.getClient(faceOpts);

        // ---- UI ----
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        TextView title = new TextView(this);
        title.setText("AutonomousEye — Face Box");
        title.setTextSize(20);
        root.addView(title);

        urlInput = new EditText(this);
        urlInput.setText("rtsp://admin:123456@192.168.0.112:554/0/av1");
        root.addView(urlInput);

        Button playBtn = new Button(this);
        playBtn.setText("Воспроизвести");
        root.addView(playBtn);

        Button detectBtn = new Button(this);
        detectBtn.setText("Старт детектор лиц");
        root.addView(detectBtn);

        Button stopBtn = new Button(this);
        stopBtn.setText("Стоп");
        root.addView(stopBtn);

        // Контейнер для видео + overlay
        FrameLayout videoContainer = new FrameLayout(this);
        LinearLayout.LayoutParams containerLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f);
        videoContainer.setLayoutParams(containerLp);

        videoLayout = new VLCVideoLayout(this);
        videoContainer.addView(videoLayout, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));

        overlay = new OverlayView(this);
        overlay.setBackgroundColor(0x00000000); // прозрачный
        videoContainer.addView(overlay, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));

        root.addView(videoContainer);
        setContentView(root);

        mediaPlayer.attachViews(videoLayout, null, false, false);

        playBtn.setOnClickListener(v -> playStream(urlInput.getText().toString()));
        detectBtn.setOnClickListener(v -> startDetection());
        stopBtn.setOnClickListener(v -> {
            stopDetection();
            mediaPlayer.stop();
            overlay.clear();
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
        Toast.makeText(this, "Детектор лиц включён", Toast.LENGTH_SHORT).show();
        handler.post(detectionLoop);
    }

    private void stopDetection() {
        detectionRunning = false;
        handler.removeCallbacks(detectionLoop);
        overlay.clear();
    }

    private final Runnable detectionLoop = new Runnable() {
        @Override
        public void run() {
            if (!detectionRunning) return;
            processFrame();
            handler.postDelayed(this, INTERVAL_MS);
        }
    };

    private void processFrame() {
        Bitmap bitmap = captureFrame();
        if (bitmap == null) return;

        InputImage image = InputImage.fromBitmap(bitmap, 0);
        faceDetector.process(image)
                .addOnSuccessListener(faces -> {
                    List<RectF> boxes = new ArrayList<>();
                    for (Face face : faces) {
                        Rect b = face.getBoundingBox();
                        // Масштабируем из координат bitmap в координаты View
                        float scaleX = (float) overlay.getWidth() / bitmap.getWidth();
                        float scaleY = (float) overlay.getHeight() / bitmap.getHeight();
                        RectF scaled = new RectF(
                                b.left * scaleX,
                                b.top * scaleY,
                                b.right * scaleX,
                                b.bottom * scaleY
                        );
                        boxes.add(scaled);
                    }
                    overlay.setBoxes(boxes);
                })
                .addOnFailureListener(e -> { /* пропускаем кадр */ });
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
