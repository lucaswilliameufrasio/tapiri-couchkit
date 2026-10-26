package com.lucas.firehome;

import android.graphics.*;
import android.graphics.drawable.Drawable;

/** Icones vetoriais simples (engrenagem, raio, wifi) desenhados em Canvas. */
class GlyphDrawable extends Drawable {
    private final String kind; private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);

    GlyphDrawable(String kind) { this.kind = kind; p.setColor(Color.WHITE); p.setStrokeCap(Paint.Cap.ROUND); p.setStrokeJoin(Paint.Join.ROUND); }

    @Override public void draw(Canvas c) {
        Rect b = getBounds(); float s = Math.min(b.width(), b.height()), cx = b.exactCenterX(), cy = b.exactCenterY();
        p.setStyle(Paint.Style.STROKE); p.setStrokeWidth(s * 0.08f);
        if (kind.equals("gear")) {
            c.drawCircle(cx, cy, s * 0.16f, p);
            for (int i = 0; i < 8; i++) {
                c.save(); c.rotate(i * 45, cx, cy);
                p.setStyle(Paint.Style.FILL); c.drawRoundRect(new RectF(cx - s * 0.06f, cy - s * 0.42f, cx + s * 0.06f, cy - s * 0.28f), s * 0.03f, s * 0.03f, p);
                c.restore();
            }
            p.setStyle(Paint.Style.STROKE); c.drawCircle(cx, cy, s * 0.30f, p);
        } else if (kind.equals("bolt")) {
            Path path = new Path();
            path.moveTo(cx + s * 0.08f, cy - s * 0.42f); path.lineTo(cx - s * 0.22f, cy + s * 0.06f); path.lineTo(cx - s * 0.02f, cy + s * 0.06f);
            path.lineTo(cx - s * 0.08f, cy + s * 0.42f); path.lineTo(cx + s * 0.22f, cy - s * 0.08f); path.lineTo(cx + s * 0.02f, cy - s * 0.08f); path.close();
            p.setStyle(Paint.Style.FILL); c.drawPath(path, p);
        } else {
            float y = cy + s * 0.24f;
            for (int i = 1; i <= 3; i++) { float r = s * 0.17f * i; c.drawArc(new RectF(cx - r, y - r, cx + r, y + r), 225, 90, false, p); }
            p.setStyle(Paint.Style.FILL); c.drawCircle(cx, y, s * 0.045f, p);
        }
    }
    @Override public void setAlpha(int a) { p.setAlpha(a); }
    @Override public void setColorFilter(ColorFilter f) { p.setColorFilter(f); }
    @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
}
