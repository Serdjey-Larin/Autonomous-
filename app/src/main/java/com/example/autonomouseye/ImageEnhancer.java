package com.example.autonomouseye;

import android.graphics.Bitmap;

import java.util.Arrays;

public class ImageEnhancer {

    /**
     * Median-фильтр: убирает шум, сохраняет края.
     * radius = 1 → лёгкое, быстрое
     * radius = 2 → сильнее, медленнее
     */
    public static Bitmap denoise(Bitmap src, int radius) {
        if (src == null) return null;
        try {
            int w = src.getWidth();
            int h = src.getHeight();
            int[] pixels = new int[w * h];
            src.getPixels(pixels, 0, w, 0, 0, w, h);
            int[] out = new int[w * h];

            int size = (2 * radius + 1) * (2 * radius + 1);
            int[] rVals = new int[size];
            int[] gVals = new int[size];
            int[] bVals = new int[size];

            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int count = 0;
                    for (int dy = -radius; dy <= radius; dy++) {
                        for (int dx = -radius; dx <= radius; dx++) {
                            int nx = Math.min(Math.max(x + dx, 0), w - 1);
                            int ny = Math.min(Math.max(y + dy, 0), h - 1);
                            int p = pixels[ny * w + nx];
                            rVals[count] = (p >> 16) & 0xFF;
                            gVals[count] = (p >> 8) & 0xFF;
                            bVals[count] = p & 0xFF;
                            count++;
                        }
                    }
                    Arrays.sort(rVals, 0, count);
                    Arrays.sort(gVals, 0, count);
                    Arrays.sort(bVals, 0, count);
                    int r = rVals[count / 2];
                    int g = gVals[count / 2];
                    int b = bVals[count / 2];
                    out[y * w + x] = 0xFF000000 | (r << 16) | (g << 8) | b;
                }
            }

            Bitmap result = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            result.setPixels(out, 0, w, 0, 0, w, h);
            return result;
        } catch (Exception e) {
            return src;
        }
    }

    /**
     * Unsharp mask: усиливает резкость (после деноизинга).
     * amount = 0.5 — мягко, 1.5 — агрессивно
     */
    public static Bitmap sharpen(Bitmap src, float amount) {
        if (src == null) return null;
        try {
            int w = src.getWidth();
            int h = src.getHeight();
            int[] orig = new int[w * h];
            src.getPixels(orig, 0, w, 0, 0, w, h);

            int[] blurred = new int[w * h];
            int radius = 2;
            int size = (2 * radius + 1) * (2 * radius + 1);

            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    long rSum = 0, gSum = 0, bSum = 0;
                    int count = 0;
                    for (int dy = -radius; dy <= radius; dy++) {
                        for (int dx = -radius; dx <= radius; dx++) {
                            int nx = Math.min(Math.max(x + dx, 0), w - 1);
                            int ny = Math.min(Math.max(y + dy, 0), h - 1);
                            int p = orig[ny * w + nx];
                            rSum += (p >> 16) & 0xFF;
                            gSum += (p >> 8) & 0xFF;
                            bSum += p & 0xFF;
                            count++;
                        }
                    }
                    int r = (int) (rSum / count);
                    int g = (int) (gSum / count);
                    int b = (int) (bSum / count);
                    blurred[y * w + x] = 0xFF000000 | (r << 16) | (g << 8) | b;
                }
            }

            int[] out = new int[w * h];
            for (int i = 0; i < w * h; i++) {
                int po = orig[i];
                int pb = blurred[i];
                int ro = (po >> 16) & 0xFF;
                int go = (po >> 8) & 0xFF;
                int bo = po & 0xFF;
                int rb = (pb >> 16) & 0xFF;
                int gb = (pb >> 8) & 0xFF;
                int bb = pb & 0xFF;

                int r = clamp((int) (ro + amount * (ro - rb)));
                int g = clamp((int) (go + amount * (go - gb)));
                int b = clamp((int) (bo + amount * (bo - bb)));

                out[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
            }

            Bitmap result = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            result.setPixels(out, 0, w, 0, 0, w, h);
            return result;
        } catch (Exception e) {
            return src;
        }
    }

    /** Полная обработка: деноизинг + резкость */
    public static Bitmap enhance(Bitmap src) {
        Bitmap denoised = denoise(src, 1);
        return sharpen(denoised, 0.8f);
    }

    private static int clamp(int v) {
        if (v < 0) return 0;
        if (v > 255) return 255;
        return v;
    }
}
