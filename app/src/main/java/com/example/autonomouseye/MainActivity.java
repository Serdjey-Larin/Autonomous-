package com.example.autonomouseye;

import android.os.Bundle;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;

public class MainActivity extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView tv = new TextView(this);
        tv.setText("AutonomousEye готов!");
        tv.setTextSize(22);
        tv.setPadding(48, 48, 48, 48);
        setContentView(tv);
    }
}
