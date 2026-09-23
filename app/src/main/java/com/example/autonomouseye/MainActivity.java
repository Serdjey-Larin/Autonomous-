// ... (импорты остаются)

public class MainActivity extends AppCompatActivity {

    private ExoPlayer player;
    private PlayerView playerView;
    private EditText urlInput;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // ... (создание root, title, urlInput, кнопок, playerView — без изменений)

        setContentView(root);

        player = new ExoPlayer.Builder(this).build();
        playerView.setPlayer(player);

        // Добавляем слушатель ошибок
        player.addListener(new Player.Listener() {
            @Override
            public void onPlayerError(PlaybackException error) {
                // Выводим текст ошибки прямо в поле ввода
                urlInput.setError(error.getMessage());
                // Или показываем всплывающее сообщение
                // Toast.makeText(MainActivity.this, error.getMessage(), Toast.LENGTH_LONG).show();
            }
        });

        playBtn.setOnClickListener(v -> playStream(urlInput.getText().toString()));
        stopBtn.setOnClickListener(v -> player.stop());
    }

    private void playStream(String url) {
        try {
            player.stop();
            // Принудительно используем TCP, чтобы избежать проблем с UDP
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

    // ... (onStop и onDestroy без изменений)
}
