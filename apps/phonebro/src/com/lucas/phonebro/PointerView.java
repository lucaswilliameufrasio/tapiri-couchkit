package com.lucas.phonebro;

import android.content.Context;
import android.graphics.*;
import android.view.View;

/** Cursor desenhado por cima do WebView; some apos alguns segundos parado. */
class PointerView extends View {
    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG), stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path arrow = new Path();
    float x, y;

    PointerView(Context c) {
        super(c);
        fill.setColor(Color.WHITE);
        stroke.setColor(Color.BLACK); stroke.setStyle(Paint.Style.STROKE); stroke.setStrokeWidth(3);
        arrow.moveTo(0, 0); arrow.lineTo(0, 34); arrow.lineTo(9, 26); arrow.lineTo(16, 42); arrow.lineTo(23, 39); arrow.lineTo(16, 24); arrow.lineTo(27, 24); arrow.close();
        setVisibility(INVISIBLE);
    }

    @Override protected void onDraw(Canvas c) {
        c.save(); c.translate(x, y); c.drawPath(arrow, fill); c.drawPath(arrow, stroke); c.restore();
    }
}
