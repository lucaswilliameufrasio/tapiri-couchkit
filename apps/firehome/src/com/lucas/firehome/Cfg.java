package com.lucas.firehome;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.URL;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Estado global do FireHome: configuracao (JSON), servidor web de personalizacao e rotas da API. */
final class Cfg {
    static volatile String url = "", token = "", weather = "";
    static volatile int port;
    private static Context app; private static ConfigServer server; private static JSONObject cfg; private static SharedPreferences prefs;
    private static long weatherAt;

    static final String[] DEFAULT_PINS = {
        "com.netflix.ninja", "com.amazon.firetv.youtube", "com.hbo.hbonow", "tv.pluto.android", "tv.twitch.android.viewer",
        "com.apple.atve.amazon.appletv", "com.limelight", "com.lucas.phonebro"};
    static final String[] DEFAULT_HIDE = {"Game Center", "Kids", "Live Shopping", "miniTV", "Amazon Music", "Amazon Photos", "Shop", "IMDb", "Naatyam", "Notícias", "Appstore"};
    static final String[] TOOLS = {"settings", "clean", "wifi", "customize"};

    static synchronized void ensureStarted(Context ctx) {
        if (server != null) return;
        app = ctx.getApplicationContext();
        prefs = app.getSharedPreferences("firehome", Context.MODE_PRIVATE);
        token = prefs.getString("token", null);
        if (token == null) { token = UUID.randomUUID().toString().substring(0, 8); prefs.edit().putString("token", token).apply(); }
        load();
        ConfigServer s = new ConfigServer(new ConfigServer.Handler() {
            public ConfigServer.Resp handle(String m, String path, Map<String, String> q, long len, InputStream body) throws Exception { return route(m, path, q, len, body); }
        });
        try { port = s.bind(prefs.getInt("port", 0)); prefs.edit().putInt("port", port).apply(); } catch (java.io.IOException e) { return; }
        server = s; s.start();
        url = "http://" + localIp() + ":" + port + "/?k=" + token;
    }

    static String localIp() {
        try { for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) for (InetAddress a : Collections.list(ni.getInetAddresses())) if (!a.isLoopbackAddress() && a instanceof Inet4Address) return a.getHostAddress(); }
        catch (Exception ignored) { }
        return "127.0.0.1";
    }

    static String q(String s) { return JSONObject.quote(s == null ? "" : s); }

    // ---------- Configuracao ----------
    private static JSONObject defaults() throws Exception {
        JSONObject d = new JSONObject();
        d.put("theme", new JSONObject().put("bg", new JSONArray().put("#0B1020").put("#1B1140").put("#3A1550")).put("accent", "#5CC8FF")
            .put("radius", 14).put("scale", 100).put("labelSize", 14));
        d.put("wallpaper", new JSONObject().put("on", false).put("dim", 55));
        d.put("header", new JSONObject().put("clock", true).put("date", true).put("ram", true).put("h24", true).put("greeting", "").put("city", ""));
        d.put("hint", true);
        d.put("rows", new JSONArray()
            .put(new JSONObject().put("id", "fav").put("type", "pins").put("title", "Favoritos").put("show", true).put("big", true))
            .put(new JSONObject().put("id", "all").put("type", "all").put("title", "Todos os apps").put("show", true).put("big", false))
            .put(new JSONObject().put("id", "sys").put("type", "tools").put("title", "Sistema").put("show", true).put("big", false)));
        d.put("pins", strings(DEFAULT_PINS)); d.put("hidden", new JSONArray()); d.put("hideLabels", strings(DEFAULT_HIDE));
        d.put("names", new JSONObject()); d.put("tools", strings(TOOLS));
        return d;
    }

    private static JSONArray strings(String[] a) { JSONArray r = new JSONArray(); for (String s : a) r.put(s); return r; }

    /** Completa o que faltar com os padroes (um nivel de profundidade nos objetos). */
    private static JSONObject merge(JSONObject base, JSONObject in) throws Exception {
        JSONObject out = new JSONObject(base.toString());
        Iterator<String> it = in.keys();
        while (it.hasNext()) {
            String k = it.next(); Object v = in.get(k);
            if (!out.has(k)) continue; // ignora chaves desconhecidas
            Object cur = out.get(k);
            if (cur instanceof JSONObject && v instanceof JSONObject && !k.equals("names")) {
                JSONObject c = (JSONObject) cur, n = (JSONObject) v; Iterator<String> ni = n.keys();
                while (ni.hasNext()) { String nk = ni.next(); if (c.has(nk) && sameKind(c.get(nk), n.get(nk))) c.put(nk, n.get(nk)); }
            } else if (sameKind(cur, v)) out.put(k, v);
        }
        return out;
    }

    private static final java.util.regex.Pattern COLOR = java.util.regex.Pattern.compile("#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})");

    /** Cores invalidas voltam ao padrao (a TV nunca recebe uma cor que nao consegue interpretar). */
    private static void sanitizeColors(JSONObject out, JSONObject def) throws Exception {
        JSONObject t = out.getJSONObject("theme"), dt = def.getJSONObject("theme");
        if (!COLOR.matcher(t.optString("accent", "")).matches()) t.put("accent", dt.getString("accent"));
        JSONArray bg = t.getJSONArray("bg"), dbg = dt.getJSONArray("bg"), fixed = new JSONArray();
        for (int i = 0; i < 3; i++) { String c = i < bg.length() ? bg.optString(i, "") : ""; fixed.put(COLOR.matcher(c).matches() ? c : dbg.getString(i)); }
        t.put("bg", fixed);
    }

    private static boolean sameKind(Object a, Object b) { return a.getClass() == b.getClass() || (a instanceof Number && b instanceof Number); }

    private static void load() {
        try {
            JSONObject d = defaults(); String raw = prefs.getString("config", null);
            if (raw != null) { cfg = merge(d, new JSONObject(raw)); sanitizeColors(cfg, d); }
            else {
                cfg = d; String legacy = prefs.getString("pins", null); // favoritos da versao antiga
                if (legacy != null) { JSONArray p = new JSONArray(); for (String s : legacy.split(",")) if (!s.isEmpty()) p.put(s); cfg.put("pins", p); }
            }
        } catch (Exception e) { try { cfg = defaults(); } catch (Exception ignored) { } }
    }

    static synchronized JSONObject snapshot() { try { return new JSONObject(cfg.toString()); } catch (Exception e) { return new JSONObject(); } }

    static synchronized void save(JSONObject c) throws Exception {
        cfg = merge(defaults(), c); sanitizeColors(cfg, defaults()); prefs.edit().putString("config", cfg.toString()).apply();
        weatherAt = 0; HomeActivity.refresh();
    }

    static synchronized void reset() throws Exception { cfg = defaults(); prefs.edit().remove("config").apply(); weatherAt = 0; HomeActivity.refresh(); }

    static File wallpaperFile() { return new File(app.getFilesDir(), "wallpaper.jpg"); }

    // ---------- Clima (Open-Meteo, so se houver cidade) ----------
    static void updateWeather() {
        final String city; synchronized (Cfg.class) { city = cfg.optJSONObject("header").optString("city", ""); }
        if (city.isEmpty()) { weather = ""; return; }
        if (System.currentTimeMillis() - weatherAt < 30 * 60 * 1000 && !weather.isEmpty()) return;
        weatherAt = System.currentTimeMillis();
        new Thread(new Runnable() { public void run() {
            try {
                JSONObject g = new JSONObject(get("https://geocoding-api.open-meteo.com/v1/search?count=1&language=pt&name=" + java.net.URLEncoder.encode(city, "UTF-8")));
                JSONObject r = g.getJSONArray("results").getJSONObject(0);
                JSONObject f = new JSONObject(get("https://api.open-meteo.com/v1/forecast?latitude=" + r.getDouble("latitude") + "&longitude=" + r.getDouble("longitude") + "&current=temperature_2m"));
                weather = r.getString("name") + " " + Math.round(f.getJSONObject("current").getDouble("temperature_2m")) + "°";
            } catch (Exception e) { weather = ""; weatherAt = 0; }
        } }).start();
    }

    private static String get(String u) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(u).openConnection(); c.setConnectTimeout(6000); c.setReadTimeout(8000);
        InputStream in = c.getInputStream(); ByteArrayOutputStream o = new ByteArrayOutputStream(); byte[] b = new byte[4096]; int n;
        while ((n = in.read(b)) > 0) o.write(b, 0, n); in.close(); return o.toString("UTF-8");
    }

    // ---------- Rotas ----------
    private static ConfigServer.Resp route(String method, String path, Map<String, String> q, long len, InputStream body) throws Exception {
        if (path.equals("/")) return ConfigServer.Resp.html(asset("firehome.html"));
        if (!path.startsWith("/api/") || !token.equals(q.get("k"))) return ConfigServer.Resp.text(403, "text/plain", "forbidden");
        String cmd = path.substring(5);
        if (cmd.equals("state")) return ConfigServer.Resp.json("{\"app\":\"firehome\",\"v\":1,\"port\":" + port + ",\"wallpaper\":" + wallpaperFile().exists() + "}");
        if (cmd.equals("config")) {
            if (method.equals("POST")) {
                if (len <= 0 || len > 200000) return ok(false, "corpo inválido");
                byte[] b = new byte[(int) len]; int off = 0, n;
                while (off < len && (n = body.read(b, off, (int) len - off)) > 0) off += n;
                save(new JSONObject(new String(b, 0, off, "UTF-8"))); return ok(true, "salvo");
            }
            return ConfigServer.Resp.json(snapshot().put("wallpaperFile", wallpaperFile().exists()).toString());
        }
        if (cmd.equals("reset")) { reset(); return ok(true, "padrões restaurados"); }
        if (cmd.equals("apps")) return ConfigServer.Resp.json(apps());
        if (cmd.equals("icon")) return icon(q.get("pkg"));
        if (cmd.equals("preview")) return preview();
        if (cmd.equals("wallpaper")) return wallpaper(len, body);
        if (cmd.equals("wallpaperclear")) { wallpaperFile().delete(); HomeActivity.refresh(); return ok(true, "removido"); }
        return ConfigServer.Resp.text(404, "application/json", "{\"ok\":false}");
    }

    private static ConfigServer.Resp ok(boolean ok, String msg) { return ConfigServer.Resp.json("{\"ok\":" + ok + ",\"msg\":" + q(msg) + "}"); }

    private static String asset(String name) throws Exception {
        InputStream in = app.getAssets().open(name); ByteArrayOutputStream o = new ByteArrayOutputStream(); byte[] b = new byte[8192]; int n;
        while ((n = in.read(b)) > 0) o.write(b, 0, n); in.close(); return o.toString("UTF-8");
    }

    private static String apps() {
        android.content.pm.PackageManager pm = app.getPackageManager(); Map<String, String> m = new TreeMap<String, String>();
        for (int pass = 0; pass < 2; pass++) {
            android.content.Intent i = new android.content.Intent(android.content.Intent.ACTION_MAIN).addCategory(pass == 0 ? android.content.Intent.CATEGORY_LEANBACK_LAUNCHER : android.content.Intent.CATEGORY_LAUNCHER);
            for (android.content.pm.ResolveInfo ri : pm.queryIntentActivities(i, 0)) {
                String pkg = ri.activityInfo.packageName; if (pkg.equals(app.getPackageName()) || m.containsKey(pkg)) continue;
                if (pass == 1 && (ri.activityInfo.applicationInfo.flags & android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0) continue;
                m.put(pkg, String.valueOf(ri.loadLabel(pm)));
            }
        }
        StringBuilder b = new StringBuilder("["); boolean first = true;
        for (Map.Entry<String, String> e : m.entrySet()) { b.append(first ? "" : ",").append("{\"pkg\":").append(q(e.getKey())).append(",\"label\":").append(q(e.getValue())).append("}"); first = false; }
        return b.append("]").toString();
    }

    private static ConfigServer.Resp icon(String pkg) throws Exception {
        Drawable d = app.getPackageManager().getApplicationIcon(pkg);
        Bitmap bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888); Canvas c = new Canvas(bmp); d.setBounds(0, 0, 96, 96); d.draw(c);
        ByteArrayOutputStream o = new ByteArrayOutputStream(); bmp.compress(Bitmap.CompressFormat.PNG, 100, o);
        return new ConfigServer.Resp(200, "image/png", o.toByteArray(), "max-age=3600");
    }

    /** Imagem enviada pelo celular: reduz para no maximo 1920 px de largura e guarda como JPEG. */
    private static ConfigServer.Resp wallpaper(long len, InputStream body) throws Exception {
        if (len <= 0 || len > 12L * 1024 * 1024) return ok(false, "imagem muito grande (máx. 12 MB)");
        byte[] b = new byte[(int) len]; int off = 0, n;
        while (off < len && (n = body.read(b, off, (int) len - off)) > 0) off += n;
        BitmapFactory.Options o = new BitmapFactory.Options(); o.inJustDecodeBounds = true; BitmapFactory.decodeByteArray(b, 0, off, o);
        if (o.outWidth <= 0) return ok(false, "não é uma imagem");
        int sample = 1; while (o.outWidth / (sample * 2) >= 1920) sample *= 2;
        o = new BitmapFactory.Options(); o.inSampleSize = sample;
        Bitmap bmp = BitmapFactory.decodeByteArray(b, 0, off, o); if (bmp == null) return ok(false, "não consegui ler a imagem");
        FileOutputStream f = new FileOutputStream(wallpaperFile()); bmp.compress(Bitmap.CompressFormat.JPEG, 88, f); f.close(); bmp.recycle();
        JSONObject c = snapshot(); c.getJSONObject("wallpaper").put("on", true); save(c);
        return ok(true, "papel de parede aplicado");
    }

    private static ConfigServer.Resp preview() throws Exception {
        byte[] jpg = HomeActivity.snapshotJpeg();
        if (jpg == null) return ConfigServer.Resp.text(503, "application/json", "{\"ok\":false,\"msg\":\"FireHome não está na tela\"}");
        return new ConfigServer.Resp(200, "image/jpeg", jpg, "no-store");
    }

    static byte[] drawToJpeg(final android.view.View v, final android.app.Activity a) throws Exception {
        final byte[][] out = new byte[1][]; final CountDownLatch done = new CountDownLatch(1);
        a.runOnUiThread(new Runnable() { public void run() {
            try {
                int w = v.getWidth(), h = v.getHeight(); if (w <= 0) return;
                Bitmap bmp = Bitmap.createBitmap(w / 2, h / 2, Bitmap.Config.RGB_565); Canvas c = new Canvas(bmp); c.scale(0.5f, 0.5f); v.draw(c);
                ByteArrayOutputStream o = new ByteArrayOutputStream(); bmp.compress(Bitmap.CompressFormat.JPEG, 80, o); out[0] = o.toByteArray(); bmp.recycle();
            } catch (Throwable ignored) { } finally { done.countDown(); }
        } });
        done.await(4, TimeUnit.SECONDS); return out[0];
    }
}
