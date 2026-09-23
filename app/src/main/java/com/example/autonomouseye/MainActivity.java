package com.example.autonomouseye;

import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.rtsp.RtspMediaSource;
import androidx.media3.ui.PlayerView;

public class MainActivity extends AppCompatActivity {

    private ExoPlayer player;
    private PlayerView playerView;
    private EditText urlInput;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        TextView title = new TextView(this);
        title.setText("AutonomousEye — RTSP");
        title.setTextSize(20);
        root.addView(title);

        urlInput = new EditText(this);
        urlInput.setHint("rtsp://admin:123456@192.168.1.100:554");
        urlInput.setText("rtsp://admin:123456@192.168.1.100:554");
        root.addView(urlInput);

        Button playBtn = new Button(this);
        playBtn.setText("Воспроизвести");
        root.addView(playBtn);

        Button stopBtn = new Button(this);
        stopBtn.setText("Стоп");
        root.addView(stopBtn);

        playerView = new PlayerView(this);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f);
        playerView.setLayoutParams(lp);
        root.addView(playerView);

        setContentView(root);

        player = new ExoPlayer.Builder(this).build();
        playerView.setPlayer(player);

        player.addListener(new Player.Listener() {
            @Override
            public void onPlayerError(PlaybackException error) {
                urlInput.setError(error.getMessage());
            }
        });

        playBtn.setOnClickListener(v -> playStream(urlInput.getText().toString()));
        stopBtn.setOnClickListener(v -> player.stop());
    }

    private void playStream(String url) {
        try {
            player.stop();
            RtspMediaSource rtsp = new RtspMediaSource.Factory()
                    .setForceUseRtpTcp(true)
                    .createMediaSource(MediaItem.fromUri(url));
            player.setMediaSource(rtsp);
            player.prepare();
            player.play();
        } catch (Exception e) {
            urlInput.setError(e.getMessage());
        }
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (player != null) player.pause();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (player != null) player.release();
    }
}
