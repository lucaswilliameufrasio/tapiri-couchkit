package com.lucas.homecam;

import com.lucas.common.Pair;
import android.content.Context;
import android.content.SharedPreferences;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.URL;
import java.util.*;

import org.json.JSONObject;

/** Estado global (endereco do go2rtc) + rotas da API de configuracao do HomeCam. */
final class Cam {
    static volatile String url = "", token = "";
    static volatile int port;
    private static Context app; private static CamServer server; private static SharedPreferences prefs;

    static synchronized void ensureStarted(Context ctx) {
        if (server != null) return;
        app = ctx.getApplicationContext();
        prefs = app.getSharedPreferences("cam", Context.MODE_PRIVATE);
        token = Pair.init(app, prefs);
        CamServer s = new CamServer(new CamServer.Handler() {
            public CamServer.Resp handle(String m, String path, Map<String, String> q, long len, InputStream body) throws Exception { return route(m, path, q); }
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

    static String q(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (char c : s.toCharArray()) { if (c == '"' || c == '\\') b.append('\\').append(c); else if (c < 32) b.append(' '); else b.append(c); }
        return b.append('"').toString();
    }

    private static String asset(String name) throws Exception {
        InputStream in = app.getAssets().open(name); ByteArrayOutputStream o = new ByteArrayOutputStream(); byte[] b = new byte[8192]; int n;
        while ((n = in.read(b)) > 0) o.write(b, 0, n); in.close(); return o.toString("UTF-8");
    }

    static String g2r() { return prefs.getString("g2r", ""); }

    static byte[] fetch(String u, int timeoutMs) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(u).openConnection(); c.setConnectTimeout(timeoutMs); c.setReadTimeout(timeoutMs);
        InputStream in = c.getInputStream(); ByteArrayOutputStream o = new ByteArrayOutputStream(); byte[] b = new byte[16384]; int n;
        while ((n = in.read(b)) > 0) o.write(b, 0, n); in.close(); c.disconnect(); return o.toByteArray();
    }

    /** Nomes das cameras do go2rtc (GET /api/streams), ordenados. Lanca excecao se inacessivel. */
    static List<String> streams() throws Exception {
        JSONObject j = new JSONObject(new String(fetch(g2r() + "/api/streams", 4000), "UTF-8"));
        List<String> l = new ArrayList<String>(); Iterator<String> it = j.keys(); while (it.hasNext()) l.add(it.next());
        Collections.sort(l); return l;
    }

    static CamServer.Resp route(String method, String path, Map<String, String> q) throws Exception {
        if (path.equals("/")) return CamServer.Resp.html(asset("cam.html"));
        if (!path.startsWith("/api/")) return CamServer.Resp.text(404, "text/plain", "nao encontrado");
        if (!Pair.token().equals(q.get("k"))) return CamServer.Resp.text(403, "application/json", "{\"ok\":false,\"error\":\"token\"}");
        if (path.equals("/api/set")) {
            String u = q.get("u") == null ? "" : q.get("u").trim();
            if (!u.isEmpty() && !u.matches("(?i)https?://.+")) u = "http://" + u;
            if (u.endsWith("/")) u = u.substring(0, u.length() - 1);
            prefs.edit().putString("g2r", u).apply();
        }
        if (path.equals("/api/set") || path.equals("/api/get")) {
            StringBuilder b = new StringBuilder("{\"url\":" + q(g2r()) + ",");
            try { List<String> l = streams(); b.append("\"ok\":true,\"cams\":["); for (int i = 0; i < l.size(); i++) b.append(i > 0 ? "," : "").append(q(l.get(i))); b.append("]}"); }
            catch (Exception e) { b.append("\"ok\":false,\"cams\":[],\"error\":").append(q(g2r().isEmpty() ? "informe o endereço" : "não consegui falar com o go2rtc")).append("}"); }
            return CamServer.Resp.json(b.toString());
        }
        return CamServer.Resp.text(404, "application/json", "{\"ok\":false}");
    }
}
