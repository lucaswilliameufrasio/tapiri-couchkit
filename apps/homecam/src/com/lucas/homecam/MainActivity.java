package com.lucas.homecam;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.SurfaceView;
import android.view.View;
import android.view.WindowManager;
import android.widget.*;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;

import java.util.*;

/** Grade de cameras do go2rtc (snapshots) + tela cheia (HLS, com modo compativel por snapshots). MENU abre o QR de configuracao. */
public class MainActivity extends Activity {
    private final Handler ui = new Handler(Looper.getMainLooper());
    private float dp; private FrameLayout root; private LinearLayout page, gridHost, qrBox; private TextView status;
    private final List<Cam.Cell> cells = new ArrayList<Cam.Cell>(); private final Map<String, ImageView> thumbs = new HashMap<String, ImageView>();
    private volatile boolean running; private Thread worker; private int cols = 3;
    // tela cheia
    private FrameLayout full; private SurfaceView video; private androidx.media3.exoplayer.ExoPlayer player; private ImageView fullImg; private TextView fullLabel; private int cur = -1; private boolean compat; private volatile int fullGen;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        dp = getResources().getDisplayMetrics().density;
        Cam.ensureStarted(this);
        try { Intent s = new Intent(this, CamService.class); if (Build.VERSION.SDK_INT >= 26) startForegroundService(s); else startService(s); } catch (Exception ignored) { }

        root = new FrameLayout(this);
        root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{0xFF0a0f10, 0xFF132226, 0xFF1d3338}));
        page = new LinearLayout(this); page.setOrientation(LinearLayout.VERTICAL); page.setPadding(px(48), px(28), px(48), px(20));
        TextView title = tv(34, Color.WHITE, true); title.setText("HomeCam");
        status = tv(16, 0x99FFFFFF, false); status.setPadding(0, px(2), 0, px(14));
        ScrollView sv = new ScrollView(this); sv.setFillViewport(true); sv.setClipToPadding(false);
        gridHost = new LinearLayout(this); gridHost.setOrientation(LinearLayout.VERTICAL); sv.addView(gridHost);
        page.addView(title); page.addView(status); page.addView(sv, new LinearLayout.LayoutParams(-1, 0, 1));
        TextView hint = tv(15, 0x88FFFFFF, false); hint.setText("OK abrir câmera · MENU configurar pelo celular"); hint.setPadding(0, px(8), 0, 0);
        page.addView(hint);
        root.addView(page, new FrameLayout.LayoutParams(-1, -1));

        qrBox = new LinearLayout(this); qrBox.setOrientation(LinearLayout.VERTICAL); qrBox.setGravity(Gravity.CENTER_HORIZONTAL); qrBox.setVisibility(View.GONE); qrBox.setPadding(px(24), px(20), px(24), px(20));
        GradientDrawable qb = new GradientDrawable(); qb.setColor(0xEE101c20); qb.setCornerRadius(px(18)); qrBox.setBackground(qb);
        ImageView qr = new ImageView(this); qr.setImageBitmap(qr(Cam.url, 360)); qr.setPadding(px(10), px(10), px(10), px(10));
        GradientDrawable w = new GradientDrawable(); w.setColor(Color.WHITE); w.setCornerRadius(px(12)); qr.setBackground(w);
        TextView qt = tv(16, 0xFFFFB27A, true); qt.setText(Cam.url); qt.setTextSize(15); qt.setPadding(0, px(8), 0, 0);
        TextView qh = tv(14, 0xAAFFFFFF, false); qh.setText("Informe o endereço do go2rtc (ex.: http://192.168.0.10:1984)");
        qt.setGravity(Gravity.CENTER); qh.setGravity(Gravity.CENTER); qh.setPadding(0, px(4), 0, 0);
        qrBox.addView(qr, new LinearLayout.LayoutParams(px(190), px(190))); qrBox.addView(qt, new LinearLayout.LayoutParams(-1, -2)); qrBox.addView(qh, new LinearLayout.LayoutParams(-1, -2));
        root.addView(qrBox, new FrameLayout.LayoutParams(px(520), -2, Gravity.CENTER));

        full = new FrameLayout(this); full.setBackgroundColor(Color.BLACK); full.setVisibility(View.GONE);
        video = new SurfaceView(this); full.addView(video, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
        fullImg = new ImageView(this); fullImg.setScaleType(ImageView.ScaleType.FIT_CENTER); full.addView(fullImg, new FrameLayout.LayoutParams(-1, -1));
        fullLabel = tv(20, Color.WHITE, true); fullLabel.setPadding(px(24), px(12), px(24), px(12)); fullLabel.setBackgroundColor(0x88000000);
        full.addView(fullLabel, new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.START));
        root.addView(full, new FrameLayout.LayoutParams(-1, -1));
        setContentView(root);
    }

    @Override protected void onResume() { super.onResume(); running = true; worker = new Thread(new Runnable() { public void run() { loop(); } }); worker.start(); }
    @Override protected void onPause() { super.onPause(); running = false; closeFull(); }

    /** Thread de fundo: atualiza a lista de cameras a cada ~20 s e os snapshots a cada ~2 s. */
    private void loop() {
        long lastList = 0;
        while (running) {
            try {
                if (System.currentTimeMillis() - lastList > 20000) {
                    lastList = System.currentTimeMillis();
                    org.json.JSONObject c = Cam.cfg();
                    int n = c.optInt("cols", 3);
                    if (c.optJSONArray("servers").length() == 0 && c.optJSONArray("direct").length() == 0) post(Collections.<Cam.Cell>emptyList(), n, "Nenhuma câmera. Aperte MENU e configure pelo celular.");
                    else {
                        Map<String, String> errors = new LinkedHashMap<String, String>(); List<Cam.Cell> all = Cam.discover(errors), vis = new ArrayList<Cam.Cell>();
                        for (Cam.Cell x : all) if (!x.hidden) vis.add(x);
                        StringBuilder st = new StringBuilder(vis.size() + " câmeras");
                        for (Map.Entry<String, String> e : errors.entrySet()) st.append(" · ").append(e.getKey()).append(": ").append(e.getValue());
                        post(vis, n, st.toString());
                        if (!errors.isEmpty()) lastList = System.currentTimeMillis() - 14000;
                    }
                }
                List<Cam.Cell> snap; synchronized (cells) { snap = new ArrayList<Cam.Cell>(cells); }
                if (fullGen > 0 && compat) { Thread.sleep(200); continue; }
                for (final Cam.Cell c : snap) {
                    if (!running) break;
                    if (c.srv == null) continue;
                    try { byte[] d = Cam.get(c.srv, "/api/frame.jpeg?src=" + Uri.encode(c.stream), 4000); final Bitmap bm = decode(d, cols > 3 ? 4 : 2);
                        ui.post(new Runnable() { public void run() { ImageView iv = thumbs.get(c.key); if (iv != null && bm != null) iv.setImageBitmap(bm); } });
                    } catch (Exception ignored) { }
                }
                Thread.sleep(1500);
            } catch (InterruptedException e) { return; }
        }
    }

    private static Bitmap decode(byte[] d, int sample) { BitmapFactory.Options o = new BitmapFactory.Options(); o.inSampleSize = sample; return BitmapFactory.decodeByteArray(d, 0, d.length, o); }

    private void post(final List<Cam.Cell> l, final int n, final String msg) {
        ui.post(new Runnable() { public void run() {
            status.setText(msg);
            boolean same = n == cols && l.size() == cells.size();
            for (int i = 0; same && i < l.size(); i++) same = l.get(i).key.equals(cells.get(i).key) && l.get(i).name.equals(cells.get(i).name);
            if (same) return;
            cols = n; synchronized (cells) { cells.clear(); cells.addAll(l); }
            rebuild();
        } });
    }

    private void rebuild() {
        gridHost.removeAllViews(); thumbs.clear(); LinearLayout row = null; boolean first = true;
        for (int i = 0; i < cells.size(); i++) {
            if (i % cols == 0) { row = new LinearLayout(this); gridHost.addView(row, new LinearLayout.LayoutParams(-1, -2)); }
            row.addView(card(i), new LinearLayout.LayoutParams(0, -2, 1));
        }
        // completa a ultima linha para os cards nao esticarem
        if (row != null) for (int k = cells.size() % cols; k != 0 && k < cols; k++) row.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
        if (!cells.isEmpty() && gridHost.getChildCount() > 0) { View c = ((LinearLayout) gridHost.getChildAt(0)).getChildAt(0); c.requestFocus(); }
    }

    private View card(final int idx) {
        final Cam.Cell cell = cells.get(idx); final String name = cell.name;
        LinearLayout c = new LinearLayout(this); c.setOrientation(LinearLayout.VERTICAL); c.setFocusable(true); c.setPadding(px(8), px(8), px(8), px(8));
        final GradientDrawable ring = new GradientDrawable(); ring.setCornerRadius(px(14)); ring.setStroke(px(3), Color.TRANSPARENT); c.setBackground(ring);
        ImageView iv = new ImageView(this); iv.setScaleType(ImageView.ScaleType.CENTER_CROP); iv.setBackgroundColor(0xFF1b2b30);
        c.addView(iv, new LinearLayout.LayoutParams(-1, px(cols > 3 ? 140 : cols == 2 ? 240 : 190)));
        if (cell.srv == null) { TextView ph = tv(30, 0x66FFFFFF, true); ph.setText("RTSP"); ph.setGravity(Gravity.CENTER); c.removeView(iv); FrameLayout box = new FrameLayout(this); box.setBackgroundColor(0xFF1b2b30); box.addView(ph, new FrameLayout.LayoutParams(-1, -1)); c.addView(box, new LinearLayout.LayoutParams(-1, px(cols > 3 ? 140 : cols == 2 ? 240 : 190))); }
        TextView t = tv(18, Color.WHITE, true); t.setText(name); t.setSingleLine(true); t.setPadding(px(4), px(6), 0, px(2)); c.addView(t);
        thumbs.put(cell.key, iv);
        c.setOnFocusChangeListener(new View.OnFocusChangeListener() { public void onFocusChange(View v, boolean f) { ring.setStroke(px(3), f ? 0xFFFFB27A : Color.TRANSPARENT); } });
        c.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { openFull(idx); } });
        return c;
    }

    private void openFull(int idx) {
        if (cells.isEmpty()) return;
        cur = (idx + cells.size()) % cells.size(); compat = false; fullGen++; final int gen = fullGen;
        full.setVisibility(View.VISIBLE); fullLabel.setText(cells.get(cur).name + "   ·   ◀ ▶ trocar" + (cells.get(cur).srv != null ? " · OK modo compatível" : ""));
        playHls(cells.get(cur));
    }

    private boolean playing() { return player != null && player.getPlaybackState() == androidx.media3.common.Player.STATE_READY && player.getPlayWhenReady(); }
    private void stopVideo() { if (player != null) { try { player.release(); } catch (Exception ignored) { } player = null; } }

    private void playHls(Cam.Cell cell) {
        fullImg.setVisibility(View.GONE); video.setVisibility(View.VISIBLE); stopVideo();
        androidx.media3.datasource.DefaultHttpDataSource.Factory http = new androidx.media3.datasource.DefaultHttpDataSource.Factory();
        if (cell.srv != null && cell.srv.auth != null) { Map<String, String> h = new HashMap<String, String>(); h.put("Authorization", cell.srv.auth); http.setDefaultRequestProperties(h); }
        player = new androidx.media3.exoplayer.ExoPlayer.Builder(this).setMediaSourceFactory(new androidx.media3.exoplayer.source.DefaultMediaSourceFactory(http)).build();
        player.setVideoSurfaceView(video);
        player.addListener(new androidx.media3.common.Player.Listener() { public void onPlayerError(androidx.media3.common.PlaybackException e) { if (!compat && full.getVisibility() == View.VISIBLE) startCompat(); } });
        String u = cell.srv != null ? cell.srv.url + "/api/stream.m3u8?src=" + Uri.encode(cell.stream) : cell.direct;
        player.setMediaItem(androidx.media3.common.MediaItem.fromUri(Uri.parse(u)));
        player.setPlayWhenReady(true); player.prepare();
        final int gen = fullGen; // se o video nao comecar em 8 s, cai para o modo compativel
        ui.postDelayed(new Runnable() { public void run() { if (fullGen == gen && !compat && full.getVisibility() == View.VISIBLE && !playing()) startCompat(); } }, 8000);
    }

    /** Modo compativel: snapshots em ~5 fps (sem codec de video). */
    private void startCompat() {
        final Cam.Cell cell = cells.get(cur); final String name = cell.name;
        if (cell.srv == null) { stopVideo(); video.setVisibility(View.GONE); fullImg.setVisibility(View.GONE); fullLabel.setText(name + "   ·   não consegui abrir o RTSP (RTMP e outras fontes: use um go2rtc)"); return; }
        compat = true; final int gen = ++fullGen;
        stopVideo(); video.setVisibility(View.GONE); fullImg.setVisibility(View.VISIBLE);
        fullLabel.setText(name + "   ·   modo compatível · OK volta ao vídeo");
        new Thread(new Runnable() { public void run() {
            while (running && fullGen == gen && compat) {
                try { byte[] d = Cam.get(cell.srv, "/api/frame.jpeg?src=" + Uri.encode(cell.stream), 4000); final Bitmap bm = decode(d, 1);
                    ui.post(new Runnable() { public void run() { if (fullGen == gen && bm != null) fullImg.setImageBitmap(bm); } }); Thread.sleep(150);
                } catch (Exception e) { try { Thread.sleep(500); } catch (InterruptedException ie) { return; } }
            }
        } }).start();
    }

    private void closeFull() { fullGen = 0; compat = false; stopVideo(); full.setVisibility(View.GONE); }

    /** Com a tela cheia aberta, as teclas nao podem chegar nos cards da grade (que ainda tem foco). */
    @Override public boolean dispatchKeyEvent(KeyEvent e) {
        if (full.getVisibility() == View.VISIBLE && e.getAction() == KeyEvent.ACTION_DOWN && e.getRepeatCount() == 0) return onKeyDown(e.getKeyCode(), e);
        if (full.getVisibility() == View.VISIBLE) return true;
        return super.dispatchKeyEvent(e);
    }

    @Override public boolean onKeyDown(int k, KeyEvent e) {
        if (full.getVisibility() == View.VISIBLE) {
            if (k == KeyEvent.KEYCODE_BACK) { closeFull(); return true; }
            if (k == KeyEvent.KEYCODE_DPAD_RIGHT) { openFull(cur + 1); return true; }
            if (k == KeyEvent.KEYCODE_DPAD_LEFT) { openFull(cur - 1); return true; }
            if (k == KeyEvent.KEYCODE_DPAD_CENTER || k == KeyEvent.KEYCODE_ENTER) {
                if (cells.get(cur).srv == null) return true;
                if (compat) { compat = false; fullGen++; fullLabel.setText(cells.get(cur).name + "   ·   ◀ ▶ trocar · OK modo compatível"); playHls(cells.get(cur)); } else startCompat();
                return true;
            }
            return true;
        }
        if (k == KeyEvent.KEYCODE_MENU) { qrBox.setVisibility(qrBox.getVisibility() == View.VISIBLE ? View.GONE : View.VISIBLE); return true; }
        if (k == KeyEvent.KEYCODE_BACK && qrBox.getVisibility() == View.VISIBLE) { qrBox.setVisibility(View.GONE); return true; }
        return super.onKeyDown(k, e);
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
