package com.lucas.stickclock;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.URL;
import java.net.URLEncoder;
import java.util.*;

import org.json.JSONArray;
import org.json.JSONObject;

/** Estado global (config, notas, clima) + rotas da API do StickClock. */
final class Clock {
    static volatile String url = "", token = "";
    static volatile int port;
    private static Context app; private static ClockServer server; private static SharedPreferences prefs;

    static synchronized void ensureStarted(Context ctx) {
        if (server != null) return;
        app = ctx.getApplicationContext();
        prefs = app.getSharedPreferences("clock", Context.MODE_PRIVATE);
        token = prefs.getString("token", null);
        if (token == null) { token = UUID.randomUUID().toString().substring(0, 8); prefs.edit().putString("token", token).apply(); }
        ClockServer s = new ClockServer(new ClockServer.Handler() {
            public ClockServer.Resp handle(String m, String path, Map<String, String> q, long len, InputStream body) throws Exception { return route(m, path, q, len, body); }
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

    private static ClockServer.Resp ok(boolean ok, String msg) { return ClockServer.Resp.json("{\"ok\":" + ok + ",\"msg\":" + q(msg) + "}"); }

    private static String asset(String name) throws Exception {
        InputStream in = app.getAssets().open(name); ByteArrayOutputStream o = new ByteArrayOutputStream(); byte[] b = new byte[8192]; int n;
        while ((n = in.read(b)) > 0) o.write(b, 0, n); in.close(); return o.toString("UTF-8");
    }

    // ---------- notas: cada item "0|texto" (aberto) ou "1|texto" (feito), separados por \n ----------
    static synchronized List<String> notes() {
        String s = prefs.getString("notes", ""); List<String> l = new ArrayList<String>();
        for (String x : s.split("\n")) if (x.length() > 2) l.add(x);
        return l;
    }
    private static synchronized void saveNotes(List<String> l) { StringBuilder b = new StringBuilder(); for (String x : l) b.append(x).append('\n'); prefs.edit().putString("notes", b.toString()).apply(); }

    static String city() { return prefs.getString("city", ""); }

    static String get(String u) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(u).openConnection(); c.setConnectTimeout(8000); c.setReadTimeout(8000);
        InputStream in = c.getInputStream(); ByteArrayOutputStream o = new ByteArrayOutputStream(); byte[] b = new byte[8192]; int n;
        while ((n = in.read(b)) > 0) o.write(b, 0, n); in.close(); return o.toString("UTF-8");
    }

    /** Busca coordenadas da cidade (Open-Meteo, sem chave) e salva. */
    static String setCity(String name) throws Exception {
        JSONObject j = new JSONObject(get("https://geocoding-api.open-meteo.com/v1/search?count=1&language=pt&name=" + URLEncoder.encode(name, "UTF-8")));
        JSONArray r = j.optJSONArray("results"); if (r == null || r.length() == 0) return null;
        JSONObject c = r.getJSONObject(0);
        String label = c.getString("name") + (c.has("admin1") ? ", " + c.getString("admin1") : "");
        prefs.edit().putString("city", label).putString("lat", String.valueOf(c.getDouble("latitude"))).putString("lon", String.valueOf(c.getDouble("longitude"))).apply();
        return label;
    }

    /** Clima atual + 3 dias. Retorna JSON do Open-Meteo ou null sem cidade/rede. */
    static JSONObject weather() {
        String lat = prefs.getString("lat", null), lon = prefs.getString("lon", null); if (lat == null) return null;
        try { return new JSONObject(get("https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
            + "&current=temperature_2m,weather_code,apparent_temperature&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=4")); }
        catch (Exception e) { return null; }
    }

    static String wmo(int c) {
        if (c == 0) return "Céu limpo"; if (c <= 2) return "Poucas nuvens"; if (c == 3) return "Nublado";
        if (c == 45 || c == 48) return "Neblina"; if (c >= 51 && c <= 57) return "Garoa";
        if (c >= 61 && c <= 67) return "Chuva"; if (c >= 71 && c <= 77) return "Neve"; if (c >= 80 && c <= 82) return "Pancadas de chuva";
        if (c >= 95) return "Tempestade"; return "—";
    }

    static ClockServer.Resp route(String method, String path, Map<String, String> q, long len, InputStream body) throws Exception {
        if (path.equals("/")) return ClockServer.Resp.html(asset("clock.html"));
        if (!path.startsWith("/api/")) return ClockServer.Resp.text(404, "text/plain", "nao encontrado");
        if (!token.equals(q.get("k"))) return ClockServer.Resp.text(403, "application/json", "{\"ok\":false,\"error\":\"token\"}");

        if (path.equals("/api/get")) {
            StringBuilder b = new StringBuilder("{\"city\":" + q(city()) + ",\"notes\":[");
            List<String> l = notes(); for (int i = 0; i < l.size(); i++) b.append(i > 0 ? "," : "").append("{\"done\":").append(l.get(i).charAt(0) == '1').append(",\"t\":").append(q(l.get(i).substring(2))).append("}");
            return ClockServer.Resp.json(b.append("]}").toString());
        }
        if (path.equals("/api/city")) {
            String name = q.get("q") == null ? "" : q.get("q").trim(); if (name.isEmpty()) return ok(false, "digite uma cidade");
            String label = setCity(name); return label == null ? ok(false, "cidade não encontrada") : ok(true, label);
        }
        if (path.equals("/api/add")) {
            String t = q.get("t") == null ? "" : q.get("t").trim().replace("\n", " "); if (t.isEmpty()) return ok(false, "vazio");
            List<String> l = notes(); l.add("0|" + t); saveNotes(l); return ok(true, "ok");
        }
        if (path.equals("/api/toggle") || path.equals("/api/del")) {
            List<String> l = notes(); int i = Integer.parseInt(q.get("i")); if (i < 0 || i >= l.size()) return ok(false, "índice");
            if (path.equals("/api/del")) l.remove(i); else { String x = l.get(i); l.set(i, (x.charAt(0) == '1' ? "0" : "1") + x.substring(1)); }
            saveNotes(l); return ok(true, "ok");
        }
        if (path.equals("/api/clear")) { List<String> l = notes(), k = new ArrayList<String>(); for (String x : l) if (x.charAt(0) == '0') k.add(x); saveNotes(k); return ok(true, "ok"); }
        return ClockServer.Resp.text(404, "application/json", "{\"ok\":false}");
    }
}
