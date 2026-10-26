package com.lucas.stickclock;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.*;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;
import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.*;

/** Tela ambiente: relogio grande, clima e lista de notas. OK mostra/oculta o QR de edicao pelo celular. */
public class MainActivity extends Activity {
    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView time, date, temp, cond, days, notes, hint; private LinearLayout qrBox; private float dp; private String lastCity = "";
    private final Runnable tick = new Runnable() { public void run() { draw(); if (!Clock.city().equals(lastCity)) { lastCity = Clock.city(); loadWeather(); } ui.postDelayed(this, 2000); } };
    private final Runnable wx = new Runnable() { public void run() { ui.postDelayed(this, 30 * 60 * 1000); loadWeather(); } };

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        dp = getResources().getDisplayMetrics().density;
        Clock.ensureStarted(this);
        try { Intent s = new Intent(this, ClockService.class); if (Build.VERSION.SDK_INT >= 26) startForegroundService(s); else startService(s); } catch (Exception ignored) { }

        FrameLayout root = new FrameLayout(this);
        root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{0xFF050a18, 0xFF0b1730, 0xFF132a52}));
        LinearLayout row = new LinearLayout(this); row.setPadding(px(64), px(40), px(64), px(40)); row.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout left = new LinearLayout(this); left.setOrientation(LinearLayout.VERTICAL);
        time = tv(110, Color.WHITE, true); time.setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL)); time.setIncludeFontPadding(false);
        date = tv(26, 0xFFA9C4F5, false);
        temp = tv(54, 0xFFFFD54A, true); temp.setPadding(0, px(28), 0, 0);
        cond = tv(22, 0xCCFFFFFF, false);
        days = tv(18, 0x99FFFFFF, false); days.setPadding(0, px(10), 0, 0);
        left.addView(time); left.addView(date); left.addView(temp); left.addView(cond); left.addView(days);
        row.addView(left, new LinearLayout.LayoutParams(0, -2, 1.1f));

        LinearLayout right = new LinearLayout(this); right.setOrientation(LinearLayout.VERTICAL); right.setPadding(px(28), px(24), px(28), px(24));
        GradientDrawable card = new GradientDrawable(); card.setColor(0x22FFFFFF); card.setCornerRadius(px(20)); right.setBackground(card);
        TextView h = tv(20, 0xFFA9C4F5, true); h.setText("LISTA");
        notes = tv(26, Color.WHITE, false); notes.setLineSpacing(0, 1.25f); notes.setPadding(0, px(10), 0, 0);
        qrBox = new LinearLayout(this); qrBox.setOrientation(LinearLayout.VERTICAL); qrBox.setGravity(Gravity.CENTER_HORIZONTAL); qrBox.setVisibility(View.GONE);
        ImageView qr = new ImageView(this); qr.setImageBitmap(qr(Clock.url, 320)); qr.setPadding(px(10), px(10), px(10), px(10));
        GradientDrawable bg = new GradientDrawable(); bg.setColor(Color.WHITE); bg.setCornerRadius(px(14)); qr.setBackground(bg);
        TextView u = tv(16, 0xFF9CC0FF, true); u.setText(Clock.url); u.setGravity(Gravity.CENTER); u.setPadding(0, px(8), 0, 0);
        qrBox.addView(qr, new LinearLayout.LayoutParams(px(190), px(190))); qrBox.addView(u);
        right.addView(h); right.addView(notes); right.addView(qrBox);
        row.addView(right, new LinearLayout.LayoutParams(0, -2, 0.9f));
        root.addView(row, new FrameLayout.LayoutParams(-1, -1));

        hint = tv(16, 0x88FFFFFF, false); hint.setText("OK: editar pelo celular");
        FrameLayout.LayoutParams hp = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.END); hp.setMargins(0, 0, px(32), px(20));
        root.addView(hint, hp);
        setContentView(root); draw();
    }

    @Override protected void onResume() { super.onResume(); lastCity = Clock.city(); ui.post(tick); ui.post(wx); }
    @Override protected void onPause() { super.onPause(); ui.removeCallbacks(tick); ui.removeCallbacks(wx); }

    @Override public boolean onKeyDown(int k, KeyEvent e) {
        if (k == KeyEvent.KEYCODE_DPAD_CENTER || k == KeyEvent.KEYCODE_ENTER) {
            boolean show = qrBox.getVisibility() != View.VISIBLE; qrBox.setVisibility(show ? View.VISIBLE : View.GONE);
            hint.setText(show ? "OK: ocultar QR" : "OK: editar pelo celular"); return true;
        }
        return super.onKeyDown(k, e);
    }

    private void draw() {
        Date now = new Date();
        time.setText(new SimpleDateFormat("HH:mm", Locale.getDefault()).format(now));
        String d = new SimpleDateFormat("EEEE, d 'de' MMMM", new Locale("pt", "BR")).format(now); date.setText(d.substring(0, 1).toUpperCase() + d.substring(1));
        List<String> l = Clock.notes(); StringBuilder b = new StringBuilder();
        for (String x : l) b.append(x.charAt(0) == '1' ? "☑  " : "☐  ").append(x.substring(2)).append('\n');
        notes.setText(l.isEmpty() ? "Vazia. Aperte OK e escaneie o QR para adicionar itens." : b.toString().trim());
        notes.setTextColor(l.isEmpty() ? 0x88FFFFFF : Color.WHITE);
    }

    private void loadWeather() {
        new Thread(new Runnable() { public void run() {
            final JSONObject j = Clock.weather();
            ui.post(new Runnable() { public void run() {
                if (j == null) { temp.setText(Clock.city().isEmpty() ? "" : "—"); cond.setText(Clock.city().isEmpty() ? "Defina a cidade pelo celular (OK)" : "Sem dados do clima"); days.setText(""); return; }
                try {
                    JSONObject c = j.getJSONObject("current");
                    temp.setText(Math.round(c.getDouble("temperature_2m")) + "°C");
                    cond.setText(Clock.city().split(",")[0] + " · " + Clock.wmo(c.getInt("weather_code")) + " · sensação " + Math.round(c.getDouble("apparent_temperature")) + "°");
                    JSONObject dl = j.getJSONObject("daily"); JSONArray t = dl.getJSONArray("time"), mx = dl.getJSONArray("temperature_2m_max"), mn = dl.getJSONArray("temperature_2m_min"), wc = dl.getJSONArray("weather_code");
                    StringBuilder s = new StringBuilder(); SimpleDateFormat in = new SimpleDateFormat("yyyy-MM-dd", Locale.US), out = new SimpleDateFormat("EEE", new Locale("pt", "BR"));
                    for (int i = 1; i < t.length(); i++) s.append(out.format(in.parse(t.getString(i)))).append("  ").append(Math.round(mn.getDouble(i))).append("° / ").append(Math.round(mx.getDouble(i))).append("°  ").append(Clock.wmo(wc.getInt(i))).append('\n');
                    days.setText(s.toString().trim());
                } catch (Exception e) { cond.setText("Sem dados do clima"); }
            } });
        } }).start();
    }

    private int px(float v) { return (int) (v * dp + 0.5f); }
    private TextView tv(int sp, int color, boolean bold) { TextView t = new TextView(this); t.setTextSize(sp); t.setTextColor(color); if (bold) t.setTypeface(Typeface.DEFAULT_BOLD); return t; }

    private static Bitmap qr(String text, int size) {
        try {
            BitMatrix m = new QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size);
            Bitmap b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
            for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) b.setPixel(x, y, m.get(x, y) ? Color.BLACK : Color.WHITE);
            return b;
        } catch (Exception e) { return Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888); }
    }
}
