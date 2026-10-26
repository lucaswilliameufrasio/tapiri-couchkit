package com.lucas.phonecast;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.AudioManager;
import android.net.Uri;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.*;

/** Estado global + rotas da API do PhoneCast. */
final class Cast {
    static volatile String url = "", token = "", last = "";
    static volatile int port;
    private static Context app; private static CastServer server;

    static synchronized void ensureStarted(Context ctx) {
        if (server != null) return;
        app = ctx.getApplicationContext();
        SharedPreferences p = app.getSharedPreferences("cast", Context.MODE_PRIVATE);
        token = p.getString("token", null);
        if (token == null) { token = UUID.randomUUID().toString().substring(0, 8); p.edit().putString("token", token).apply(); }
        CastServer s = new CastServer(new CastServer.Handler() {
            public CastServer.Resp handle(String m, String path, Map<String, String> q, long len, InputStream body) throws Exception { return route(m, path, q, len, body); }
        });
        try { port = s.bind(p.getInt("port", 0)); p.edit().putInt("port", port).apply(); } catch (java.io.IOException e) { return; }
        server = s; s.start();
        url = "http://" + localIp() + ":" + port + "/?k=" + token;
    }

    static String localIp() {
        try { for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) for (InetAddress a : Collections.list(ni.getInetAddresses())) if (!a.isLoopbackAddress() && a instanceof Inet4Address) return a.getHostAddress(); }
        catch (Exception ignored) { }
        return "127.0.0.1";
    }

    static String q(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (char c : s.toCharArray()) { if (c == '"' || c == '\\') b.append('\\').append(c); else if (c < 32) b.append(' '); else b.append(c); }
        return b.append('"').toString();
    }

    private static CastServer.Resp ok(boolean ok, String msg) { return CastServer.Resp.json("{\"ok\":" + ok + ",\"msg\":" + q(msg) + "}"); }

    private static String asset(String name) throws Exception {
        InputStream in = app.getAssets().open(name); ByteArrayOutputStream o = new ByteArrayOutputStream(); byte[] b = new byte[8192]; int n;
        while ((n = in.read(b)) > 0) o.write(b, 0, n); in.close(); return o.toString("UTF-8");
    }

    static String kind(String name) {
        String n = name.toLowerCase(Locale.ROOT); int i = n.indexOf('?'); if (i > 0) n = n.substring(0, i);
        if (n.matches(".*\\.(jpg|jpeg|png|gif|webp|bmp)$")) return "image";
        if (n.matches(".*\\.(mp3|m4a|aac|wav|flac|ogg|opus)$")) return "audio";
        if (n.matches(".*\\.(mp4|m4v|mkv|webm|mov|3gp|ts|m3u8|avi)$")) return "video";
        return "";
    }

    private static void play(String src, String kind, String title) {
        Intent i = new Intent(app, PlayerActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("src", src).putExtra("kind", kind).putExtra("title", title);
        app.startActivity(i); last = title;
    }

    static CastServer.Resp route(String method, String path, Map<String, String> q, long len, InputStream body) throws Exception {
        if (path.equals("/")) return CastServer.Resp.html(asset("cast.html"));
        if (!path.startsWith("/api/")) return CastServer.Resp.text(404, "text/plain", "nao encontrado");
        if (!token.equals(q.get("k"))) return CastServer.Resp.text(403, "application/json", "{\"ok\":false,\"error\":\"token\"}");

        if (path.equals("/api/state")) {
            PlayerActivity p = PlayerActivity.cur;
            AudioManager am = (AudioManager) app.getSystemService(Context.AUDIO_SERVICE);
            return CastServer.Resp.json("{\"active\":" + (p != null) + ",\"title\":" + q(p != null ? p.title : "") + ",\"kind\":" + q(p != null ? p.kind : "")
                + ",\"playing\":" + (p != null && p.isPlaying()) + ",\"pos\":" + (p != null ? p.pos() : 0) + ",\"dur\":" + (p != null ? p.dur() : 0)
                + ",\"vol\":" + am.getStreamVolume(AudioManager.STREAM_MUSIC) + ",\"volMax\":" + am.getStreamMaxVolume(AudioManager.STREAM_MUSIC) + "}");
        }
        if (path.equals("/api/link")) {
            String u = q.get("url") == null ? "" : q.get("url").trim();
            if (!u.matches("(?i)https?://.+")) return ok(false, "link inválido");
            String k = kind(u);
            if (!k.isEmpty()) { play(u, k, u.substring(u.lastIndexOf('/') + 1)); return ok(true, "tocando na TV"); }
            Intent v = new Intent(Intent.ACTION_VIEW, Uri.parse(u)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            app.startActivity(v); last = u; return ok(true, "aberto na TV");
        }
        if (path.equals("/api/upload") && method.equals("POST")) {
            String name = q.get("name") == null ? "midia" : q.get("name");
            String k = kind(name); if (k.isEmpty()) k = q.get("type") != null && q.get("type").startsWith("image") ? "image" : q.get("type") != null && q.get("type").startsWith("audio") ? "audio" : "video";
            File dir = new File(app.getCacheDir(), "cast"); dir.mkdirs();
            File[] old = dir.listFiles(); if (old != null) for (File f : old) f.delete();
            String ext = name.contains(".") ? name.substring(name.lastIndexOf('.')).replaceAll("[^A-Za-z0-9.]", "") : "";
            File out = new File(dir, "cast" + System.currentTimeMillis() + ext);
            FileOutputStream fo = new FileOutputStream(out); byte[] b = new byte[65536]; long left = len; int n;
            while (left > 0 && (n = body.read(b, 0, (int) Math.min(b.length, left))) > 0) { fo.write(b, 0, n); left -= n; }
            fo.close();
            if (left > 0) { out.delete(); return ok(false, "upload incompleto"); }
            play(out.getAbsolutePath(), k, name); return ok(true, "tocando na TV");
        }
        if (path.equals("/api/ctl")) {
            String c = q.get("cmd") == null ? "" : q.get("cmd");
            AudioManager am = (AudioManager) app.getSystemService(Context.AUDIO_SERVICE);
            if (c.equals("vol")) { am.adjustStreamVolume(AudioManager.STREAM_MUSIC, "up".equals(q.get("v")) ? AudioManager.ADJUST_RAISE : AudioManager.ADJUST_LOWER, 0); return ok(true, "ok"); }
            if (c.equals("mute")) { am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_TOGGLE_MUTE, 0); return ok(true, "ok"); }
            final PlayerActivity p = PlayerActivity.cur; if (p == null) return ok(false, "nada tocando");
            final String cmd = c; final int v = q.get("v") == null ? 0 : Integer.parseInt(q.get("v"));
            p.runOnUiThread(new Runnable() { public void run() { p.control(cmd, v); } });
            return ok(true, "ok");
        }
        return CastServer.Resp.text(404, "application/json", "{\"ok\":false}");
    }
}
