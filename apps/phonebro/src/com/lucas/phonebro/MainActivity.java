package com.lucas.phonebro;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Base64;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.*;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.Collections;
import java.util.Map;
import java.util.UUID;

public class MainActivity extends Activity {
    static final String DESKTOP_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
    static final String DEFAULT_BOOKMARKS = "YouTube\thttps://www.youtube.com/tv\nGoogle\thttps://www.google.com\nTwitch\thttps://www.twitch.tv\nWikipedia\thttps://pt.wikipedia.org\nGitHub\thttps://github.com";

    private final Handler ui = new Handler(Looper.getMainLooper());
    private SharedPreferences prefs;
    private FrameLayout root;
    private WebView web;
    private PointerView pointer;
    private View overlay;
    private String token, remoteUrl = "", qrPng = "";
    private RemoteServer server;
    private int port;
    private String start;
    private int W, H;
    private float px, py;
    private boolean desktop = true, dragging;
    private float dragY;
    private View customView;
    private WebChromeClient.CustomViewCallback customCb;

    private final Runnable hidePointer = new Runnable() { public void run() { pointer.setVisibility(View.INVISIBLE); } };
    private final Runnable endDrag = new Runnable() { public void run() { endDrag(); } };

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = getSharedPreferences("phonebro", MODE_PRIVATE);
        token = prefs.getString("token", null);
        if (token == null) { token = UUID.randomUUID().toString().substring(0, 8); prefs.edit().putString("token", token).apply(); }
        desktop = prefs.getBoolean("desktop", true);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
        DisplayMetrics dm = getResources().getDisplayMetrics(); W = dm.widthPixels; H = dm.heightPixels;
        px = W / 2f; py = H / 2f;

        root = new FrameLayout(this); root.setBackgroundColor(Color.BLACK);
        web = new WebView(this); setupWeb();
        root.addView(web, new FrameLayout.LayoutParams(-1, -1));
        pointer = new PointerView(this);
        root.addView(pointer, new FrameLayout.LayoutParams(-1, -1));
        setContentView(root);

        server = new RemoteServer(new RemoteServer.Handler() {
            public RemoteServer.Response handle(String path, Map<String, String> q) { return route(path, q); }
        });
        try { port = server.bind(prefs.getInt("port", 0)); prefs.edit().putInt("port", port).apply(); } catch (java.io.IOException e) { port = 0; }
        start = "http://127.0.0.1:" + port + "/start";
        remoteUrl = "http://" + localIp() + ":" + port + "/?k=" + token;
        qrPng = qrBase64(remoteUrl);
        buildOverlay();
        server.start();
        handleIntent(getIntent());
    }

    @Override protected void onNewIntent(Intent i) { super.onNewIntent(i); handleIntent(i); }

    private void handleIntent(Intent i) {
        Uri d = i == null ? null : i.getData();
        web.loadUrl(d != null ? d.toString() : start);
    }

    @Override protected void onDestroy() { if (server != null) server.shutdown(); web.destroy(); super.onDestroy(); }

    // ---------- WebView ----------
    private void setupWeb() {
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true); s.setDatabaseEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setLoadWithOverviewMode(true); s.setUseWideViewPort(true);
        s.setSupportZoom(true); s.setBuiltInZoomControls(true); s.setDisplayZoomControls(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        applyUa();
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true);
        web.setFocusable(true); web.setFocusableInTouchMode(true); web.requestFocus();
        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient() {
            @Override public void onShowCustomView(View v, CustomViewCallback cb) {
                if (customView != null) { cb.onCustomViewHidden(); return; }
                customView = v; customCb = cb;
                root.addView(v, new FrameLayout.LayoutParams(-1, -1)); web.setVisibility(View.INVISIBLE); pointer.bringToFront();
            }
            @Override public void onHideCustomView() {
                if (customView == null) return;
                root.removeView(customView); customView = null; web.setVisibility(View.VISIBLE);
                if (customCb != null) customCb.onCustomViewHidden();
            }
        });
        web.setDownloadListener(new DownloadListener() {
            public void onDownloadStart(String url, String ua, String cd, String mime, long len) {
                try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url))); } catch (Exception ignored) { }
            }
        });
    }

    private void applyUa() { web.getSettings().setUserAgentString(desktop ? DESKTOP_UA : null); }

    private static String normalize(String in) {
        in = in.trim();
        if (in.matches("^[a-zA-Z][a-zA-Z0-9+.-]*://.*") || in.startsWith("about:")) return in;
        if (!in.contains(" ") && in.contains(".")) return "https://" + in;
        return "https://www.google.com/search?q=" + Uri.encode(in);
    }

    // ---------- Overlay com QR (tecla MENU) ----------
    private void buildOverlay() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL); box.setGravity(Gravity.CENTER_HORIZONTAL); box.setPadding(40, 40, 40, 40);
        box.setBackgroundColor(0xEE101828);
        ImageView iv = new ImageView(this); iv.setImageBitmap(qrBitmap(remoteUrl, 360));
        TextView t = new TextView(this); t.setTextColor(Color.WHITE); t.setTextSize(22); t.setGravity(Gravity.CENTER);
        t.setText("Escaneie para controlar pelo celular\n" + remoteUrl);
        box.addView(iv, new LinearLayout.LayoutParams(360, 360)); box.addView(t);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER);
        overlay = box; overlay.setVisibility(View.GONE); root.addView(overlay, lp);
    }

    private void toggleOverlay() { overlay.setVisibility(overlay.getVisibility() == View.VISIBLE ? View.GONE : View.VISIBLE); }

    // ---------- Teclas do controle remoto fisico: D-pad move o cursor ----------
    @Override public boolean dispatchKeyEvent(KeyEvent e) {
        int k = e.getKeyCode();
        if (customView != null && k != KeyEvent.KEYCODE_BACK) return super.dispatchKeyEvent(e);
        boolean down = e.getAction() == KeyEvent.ACTION_DOWN;
        switch (k) {
            case KeyEvent.KEYCODE_DPAD_UP: case KeyEvent.KEYCODE_DPAD_DOWN:
            case KeyEvent.KEYCODE_DPAD_LEFT: case KeyEvent.KEYCODE_DPAD_RIGHT:
                if (down) {
                    int step = 24 + Math.min(e.getRepeatCount() * 8, 90);
                    float dx = k == KeyEvent.KEYCODE_DPAD_LEFT ? -step : k == KeyEvent.KEYCODE_DPAD_RIGHT ? step : 0;
                    float dy = k == KeyEvent.KEYCODE_DPAD_UP ? -step : k == KeyEvent.KEYCODE_DPAD_DOWN ? step : 0;
                    boolean atTop = py <= 2 && dy < 0, atBottom = py >= H - 3 && dy > 0;
                    movePointer(dx, dy);
                    if (atTop || atBottom) scroll(dy > 0 ? 160 : -160);
                }
                return true;
            case KeyEvent.KEYCODE_DPAD_CENTER: case KeyEvent.KEYCODE_ENTER:
                if (down && e.getRepeatCount() == 0) click();
                return true;
            case KeyEvent.KEYCODE_MENU:
                if (down) toggleOverlay();
                return true;
            case KeyEvent.KEYCODE_BACK:
                if (down) goBackOrExit();
                return true;
        }
        return super.dispatchKeyEvent(e);
    }

    private void goBackOrExit() {
        if (overlay.getVisibility() == View.VISIBLE) { overlay.setVisibility(View.GONE); return; }
        if (customView != null) { web.getWebChromeClient().onHideCustomView(); return; }
        if (web.canGoBack()) web.goBack(); else finish();
    }

    // ---------- Acoes de entrada ----------
    private void movePointer(float dx, float dy) {
        px = Math.max(0, Math.min(W - 1, px + dx)); py = Math.max(0, Math.min(H - 1, py + dy));
        pointer.x = px; pointer.y = py; pointer.setVisibility(View.VISIBLE); pointer.invalidate();
        ui.removeCallbacks(hidePointer); ui.postDelayed(hidePointer, 4000);
    }

    private void click() {
        pointer.setVisibility(View.VISIBLE); ui.removeCallbacks(hidePointer); ui.postDelayed(hidePointer, 4000);
        View target = customView != null ? customView : web;
        long t = SystemClock.uptimeMillis();
        MotionEvent d = MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, px, py, 0);
        target.dispatchTouchEvent(d); d.recycle();
        final MotionEvent u = MotionEvent.obtain(t, t + 50, MotionEvent.ACTION_UP, px, py, 0);
        final View tg = target;
        ui.postDelayed(new Runnable() { public void run() { tg.dispatchTouchEvent(u); u.recycle(); } }, 50);
    }

    /** dy > 0 rola a pagina para baixo; simula um arrasto de dedo (funciona em containers internos e com inercia). */
    private void scroll(float dy) {
        long t = SystemClock.uptimeMillis();
        float x = px;
        if (!dragging) {
            dragging = true; dragY = H / 2f;
            MotionEvent d = MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, x, dragY, 0); web.dispatchTouchEvent(d); d.recycle();
        }
        dragY -= dy;
        MotionEvent m = MotionEvent.obtain(t, t, MotionEvent.ACTION_MOVE, x, dragY, 0); web.dispatchTouchEvent(m); m.recycle();
        ui.removeCallbacks(endDrag);
        if (dragY < 120 || dragY > H - 120) endDrag(); else ui.postDelayed(endDrag, 120);
    }

    private void endDrag() {
        if (!dragging) return;
        dragging = false; ui.removeCallbacks(endDrag);
        long t = SystemClock.uptimeMillis();
        MotionEvent u = MotionEvent.obtain(t, t, MotionEvent.ACTION_UP, px, dragY, 0); web.dispatchTouchEvent(u); u.recycle();
    }

    private void key(int code) {
        long t = SystemClock.uptimeMillis();
        web.requestFocus();
        web.dispatchKeyEvent(new KeyEvent(t, t, KeyEvent.ACTION_DOWN, code, 0));
        web.dispatchKeyEvent(new KeyEvent(t, t + 20, KeyEvent.ACTION_UP, code, 0));
    }

    private static String jsQuote(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (char c : s.toCharArray()) {
            if (c == '"' || c == '\\') b.append('\\').append(c);
            else if (c == '\n') b.append("\\n"); else if (c == '\r') { } else if (c < 32) b.append(' '); else b.append(c);
        }
        return b.append('"').toString();
    }

    /** Substitui o valor do campo focado (compativel com React etc.). */
    private void setText(String t) {
        web.evaluateJavascript("(function(t){var e=document.activeElement;if(!e)return;"
                + "if(e.isContentEditable){e.textContent=t;e.dispatchEvent(new Event('input',{bubbles:true}));return}"
                + "if(!('value' in e))return;var p=e.tagName=='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;"
                + "var d=Object.getOwnPropertyDescriptor(p,'value');if(d&&d.set)d.set.call(e,t);else e.value=t;"
                + "e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}))})(" + jsQuote(t) + ")", null);
    }

    private void media(String action, String arg) {
        String js;
        if (action.equals("toggle")) js = "var v=document.querySelector('video');if(v){v.paused?v.play():v.pause()}";
        else if (action.equals("seek")) js = "var v=document.querySelector('video');if(v)v.currentTime+=" + Float.parseFloat(arg);
        else js = "var v=document.querySelector('video');if(v)v.muted=!v.muted";
        web.evaluateJavascript("(function(){" + js + "})()", null);
    }

    // ---------- Rotas HTTP ----------
    private RemoteServer.Response route(final String path, final Map<String, String> q) {
        try {
            if (path.equals("/")) return RemoteServer.Response.html(asset("remote.html"));
            if (path.equals("/start")) return RemoteServer.Response.html(startPage());
            if (!path.startsWith("/api/") || !token.equals(q.get("k"))) return RemoteServer.Response.utf8(403, "text/plain", "forbidden");
            final String cmd = path.substring(5);
            ui.post(new Runnable() { public void run() { try { exec(cmd, q); } catch (Exception ignored) { } } });
            if (cmd.equals("state")) return RemoteServer.Response.json(stateJson());
            return RemoteServer.Response.json("{\"ok\":true}");
        } catch (Exception e) { return RemoteServer.Response.utf8(500, "text/plain", String.valueOf(e)); }
    }

    private String stateJson() throws Exception {
        final String[] out = new String[1];
        final Object lock = new Object();
        ui.post(new Runnable() { public void run() {
            synchronized (lock) {
                out[0] = "{\"url\":" + jsQuote(String.valueOf(web.getUrl())) + ",\"title\":" + jsQuote(String.valueOf(web.getTitle()))
                        + ",\"desktop\":" + desktop + ",\"bookmarks\":" + jsQuote(bookmarks()) + "}";
                lock.notifyAll();
            }
        } });
        synchronized (lock) { if (out[0] == null) lock.wait(1500); }
        return out[0] == null ? "{}" : out[0];
    }

    private void exec(String cmd, Map<String, String> q) {
        if (cmd.equals("move")) movePointer(Float.parseFloat(q.get("dx")), Float.parseFloat(q.get("dy")));
        else if (cmd.equals("click")) click();
        else if (cmd.equals("scroll")) scroll(Float.parseFloat(q.get("dy")));
        else if (cmd.equals("nav")) web.loadUrl(normalize(q.get("url")));
        else if (cmd.equals("back")) { if (customView != null) web.getWebChromeClient().onHideCustomView(); else if (web.canGoBack()) web.goBack(); }
        else if (cmd.equals("forward")) { if (web.canGoForward()) web.goForward(); }
        else if (cmd.equals("reload")) web.reload();
        else if (cmd.equals("home")) web.loadUrl(start);
        else if (cmd.equals("zoom")) web.zoomBy(Float.parseFloat(q.get("f")));
        else if (cmd.equals("ua")) { desktop = !desktop; prefs.edit().putBoolean("desktop", desktop).apply(); applyUa(); web.reload(); }
        else if (cmd.equals("key")) key(Integer.parseInt(q.get("code")));
        else if (cmd.equals("text")) setText(q.get("t"));
        else if (cmd.equals("media")) media(q.get("a"), q.get("v"));
        else if (cmd.equals("vol")) ((AudioManager) getSystemService(Context.AUDIO_SERVICE)).adjustStreamVolume(AudioManager.STREAM_MUSIC,
                Integer.parseInt(q.get("d")) > 0 ? AudioManager.ADJUST_RAISE : AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI);
        else if (cmd.equals("fav")) addBookmark();
        else if (cmd.equals("unfav")) removeBookmark(q.get("url"));
        else if (cmd.equals("qr")) toggleOverlay();
    }

    // ---------- Favoritos ----------
    private String bookmarks() { return prefs.getString("bookmarks", DEFAULT_BOOKMARKS); }

    private void addBookmark() {
        String url = web.getUrl(); if (url == null || url.startsWith(start)) return;
        String title = web.getTitle() == null || web.getTitle().isEmpty() ? url : web.getTitle().replace('\t', ' ').replace('\n', ' ');
        if (bookmarks().contains("\t" + url)) return;
        prefs.edit().putString("bookmarks", bookmarks() + "\n" + title + "\t" + url).apply();
    }

    private void removeBookmark(String url) {
        StringBuilder b = new StringBuilder();
        for (String l : bookmarks().split("\n")) if (!l.endsWith("\t" + url)) b.append(b.length() > 0 ? "\n" : "").append(l);
        prefs.edit().putString("bookmarks", b.toString()).apply();
    }

    private static String esc(String s) { return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;"); }

    private String startPage() {
        StringBuilder tiles = new StringBuilder();
        for (String l : bookmarks().split("\n")) {
            String[] p = l.split("\t"); if (p.length < 2) continue;
            String host = Uri.parse(p[1]).getHost();
            tiles.append("<a href=\"").append(esc(p[1])).append("\"><b>").append(esc(p[0].isEmpty() ? p[1] : p[0].substring(0, 1).toUpperCase())).append("</b><span>")
                    .append(esc(p[0])).append("</span><small>").append(esc(host == null ? "" : host)).append("</small></a>");
        }
        return "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'><style>"
                + "body{margin:0;background:linear-gradient(135deg,#0b1020,#1a2a5a);color:#fff;font:28px sans-serif;padding:48px}"
                + "h1{margin:0 0 6px;font-size:56px}p{margin:0 0 40px;opacity:.7}.g{display:flex;flex-wrap:wrap;gap:24px}"
                + "a{display:block;width:260px;padding:24px;border-radius:20px;background:#ffffff18;color:#fff;text-decoration:none}"
                + "a b{display:block;font-size:64px;margin-bottom:8px;color:#5cc8ff}a span{display:block}a small{opacity:.55;font-size:20px}"
                + ".w{display:flex;gap:48px;align-items:flex-start}.w>div:first-child{flex:1;min-width:0}.q{flex:none;text-align:center;font-size:18px;background:#fff;color:#000;padding:16px;border-radius:16px}"
                + ".q img{width:240px;height:240px;display:block}</style>"
                + "<div class=w><div><h1>PhoneBro</h1><p>Escaneie o QR code e controle este navegador pelo celular. Controle remoto: setas movem o cursor, OK clica, MENU mostra o QR.</p>"
                + "<div class=g>" + tiles + "</div></div><div class=q><img src='data:image/png;base64," + qrPng + "'>" + esc(remoteUrl) + "</div></div>";
    }

    // ---------- Utilitarios ----------
    private String asset(String name) throws Exception {
        InputStream in = getAssets().open(name); ByteArrayOutputStream o = new ByteArrayOutputStream(); byte[] b = new byte[4096]; int n;
        while ((n = in.read(b)) > 0) o.write(b, 0, n); in.close(); return o.toString("UTF-8");
    }

    private static String localIp() {
        try {
            for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces()))
                for (InetAddress a : Collections.list(ni.getInetAddresses()))
                    if (!a.isLoopbackAddress() && a instanceof Inet4Address) return a.getHostAddress();
        } catch (Exception ignored) { }
        return "127.0.0.1";
    }

    private static Bitmap qrBitmap(String text, int size) {
        try {
            BitMatrix m = new QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size);
            Bitmap bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
            for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) bmp.setPixel(x, y, m.get(x, y) ? Color.BLACK : Color.WHITE);
            return bmp;
        } catch (Exception e) { return Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888); }
    }

    private static String qrBase64(String text) {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        qrBitmap(text, 300).compress(Bitmap.CompressFormat.PNG, 100, o);
        return Base64.encodeToString(o.toByteArray(), Base64.NO_WRAP);
    }
}
