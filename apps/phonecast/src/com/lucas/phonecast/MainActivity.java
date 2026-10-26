package com.lucas.phonecast;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.*;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;

/** Tela de espera: QR code que abre a pagina de envio no celular. */
public class MainActivity extends Activity {
    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView stats; private float dp;
    private final Runnable refresh = new Runnable() { public void run() { stats.setText("Servidor ativo na porta " + Cast.port + (Cast.last.isEmpty() ? "" : "   ·   Último envio: " + Cast.last)); ui.postDelayed(this, 4000); } };

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        dp = getResources().getDisplayMetrics().density;
        Cast.ensureStarted(this);
        try { Intent s = new Intent(this, CastService.class); if (Build.VERSION.SDK_INT >= 26) startForegroundService(s); else startService(s); } catch (Exception ignored) { }

        FrameLayout root = new FrameLayout(this);
        root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{0xFF1c0c24, 0xFF3a1245, 0xFF6a1f4a}));
        LinearLayout row = new LinearLayout(this); row.setGravity(Gravity.CENTER_VERTICAL); row.setPadding(px(64), px(40), px(64), px(40));
        LinearLayout left = new LinearLayout(this); left.setOrientation(LinearLayout.VERTICAL);
        TextView title = tv(46, Color.WHITE, true); title.setText("PhoneCast");
        TextView sub = tv(20, 0xCCFFFFFF, false); sub.setText("Envie vídeos, músicas, fotos e links do celular para a TV.\nEscaneie o QR code ou digite o endereço (Android e iPhone, mesma rede Wi-Fi).");
        sub.setPadding(0, px(8), 0, px(20));
        TextView addr = tv(24, 0xFFFFB3CF, true); addr.setText(Cast.url);
        stats = tv(18, 0xAAFFFFFF, false); stats.setPadding(0, px(28), 0, 0);
        left.addView(title); left.addView(sub); left.addView(addr); left.addView(stats);
        row.addView(left, new LinearLayout.LayoutParams(0, -2, 1));
        ImageView qr = new ImageView(this); qr.setImageBitmap(qr(Cast.url, 420)); qr.setPadding(px(14), px(14), px(14), px(14));
        GradientDrawable bg = new GradientDrawable(); bg.setColor(Color.WHITE); bg.setCornerRadius(px(18)); qr.setBackground(bg);
        row.addView(qr, new LinearLayout.LayoutParams(px(240), px(240)));
        root.addView(row, new FrameLayout.LayoutParams(-1, -1));
        setContentView(root);
    }

    @Override protected void onResume() { super.onResume(); ui.post(refresh); }
    @Override protected void onPause() { super.onPause(); ui.removeCallbacks(refresh); }
    private int px(float v) { return (int) (v * dp + 0.5f); }
    private TextView tv(int sp, int color, boolean bold) { TextView t = new TextView(this); t.setTextSize(sp); t.setTextColor(color); if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT_BOLD); return t; }

    private static Bitmap qr(String text, int size) {
        try {
            BitMatrix m = new QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size);
            Bitmap b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
            for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) b.setPixel(x, y, m.get(x, y) ? Color.BLACK : Color.WHITE);
            return b;
        } catch (Exception e) { return Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888); }
    }
}
