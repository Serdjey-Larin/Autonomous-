package com.example.autonomouseye;

import android.net.Uri;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

import org.videolan.libvlc.LibVLC;
import org.videolan.libvlc.Media;
import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.util.VLCVideoLayout;

import java.util.ArrayList;

public class MainActivity extends AppCompatActivity {

    private LibVLC libVLC;
    private MediaPlayer mediaPlayer;
    private VLCVideoLayout videoLayout;
    private EditText urlInput;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ArrayList<String> options = new ArrayList<>();
        options.add("--rtsp-tcp");
        options.add("--network-caching=1500");
        options.add("--no-drop-late-frames");
        options.add("--no-skip-frames");

        libVLC = new LibVLC(this, options);
        mediaPlayer = new MediaPlayer(libVLC);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        TextView title = new TextView(this);
        title.setText("AutonomousEye — libVLC");
        title.setTextSize(20);
        root.addView(title);

        urlInput = new EditText(this);
        urlInput.setHint("rtsp://admin:123456@192.168.0.112:554/0/av1");
        urlInput.setText("rtsp://admin:123456@192.168.0.112:554/0/av1");
        root.addView(urlInput);

        Button playBtn = new Button(this);
        playBtn.setText("Воспроизвести");
        root.addView(playBtn);

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
        stopBtn.setOnClickListener(v -> mediaPlayer.stop());
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

    @Override
    protected void onStop() {
        super.onStop();
        if (mediaPlayer != null) mediaPlayer.pause();
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
