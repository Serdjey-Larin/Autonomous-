public OverlayView(Context context) {
    super(context);
    paint = new Paint();
    paint.setColor(Color.parseColor("#00FF88"));   // ярко-зелёный
    paint.setStyle(Paint.Style.STROKE);
    paint.setStrokeWidth(4f);
    paint.setAntiAlias(true);
    paint.setShadowLayer(8f, 0f, 0f, Color.parseColor("#8000FF88"));
    setLayerType(LAYER_TYPE_SOFTWARE, null);
}
