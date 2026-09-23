package com.example.autonomouseye;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;

import java.util.ArrayList;
import java.util.List;

public class OverlayView extends View {

    private final List<RectF> boxes = new ArrayList<>();
    private final Paint paint;

    public OverlayView(Context context) {
        super(context);
        paint = new Paint();
        paint.setColor(Color.GREEN);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(6f);
        paint.setAntiAlias(true);
    }

    public void setBoxes(List<RectF> newBoxes) {
        boxes.clear();
        boxes.addAll(newBoxes);
        invalidate(); // перерисовать
    }

    public void clear() {
        boxes.clear();
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        for (RectF box : boxes) {
            canvas.drawRect(box, paint);
        }
    }
}
