package com.lucas.homecam;

import com.lucas.common.Pair;
import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.URL;
import java.util.*;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Estado global + API de configuracao do HomeCam.
 * Config (JSON em prefs "cfg"): {cols, servers:[{id,name,url,user,pass}], cams:[{key,name,hidden}], direct:[{id,name,url}]}.
 * "cams" guarda ordem, apelido e visibilidade; a chave e "idDoServidor/stream" (go2rtc) ou "d:id" (RTSP direto).
 */
final class Cam {
    static volatile String url = "", token = "";
    static volatile int port;
    private static Context app; private static CamServer server; private static SharedPreferences prefs;
    private static volatile JSONObject cfg;

    /** Servidor go2rtc (com autenticacao basica opcional). */
    static final class Srv {
        final String id, name, url, auth;
        Srv(JSONObject j) {
            id = j.optString("id"); name = j.optString("name", id); url = j.optString("url");
            String u = j.optString("user"), p = j.optString("pass");
            auth = u.isEmpty() ? null : "Basic " + Base64.encodeToString((u + ":" + p).getBytes(), Base64.NO_WRAP);
        }
    }

    /** Camera exibivel: de um go2rtc (srv + stream) ou RTSP direto (direct = url). */
    static final class Cell {
        String key, name, stream, direct; Srv srv; boolean hidden;
    }

    static synchronized void ensureStarted(Context ctx) {
        if (server != null) return;
        app = ctx.getApplicationContext();
        prefs = app.getSharedPreferences("cam", Context.MODE_PRIVATE);
        token = Pair.init(app, prefs);
        CamServer s = new CamServer(new CamServer.Handler() {
            public CamServer.Resp handle(String m, String path, Map<String, String> q, long len, InputStream body) throws Exception { return route(m, path, q, len, body); }
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

    // ---- configuracao ----

    static String normUrl(String u) {
        u = u == null ? "" : u.trim();
        if (!u.isEmpty() && !u.matches("(?i)https?://.+")) u = "http://" + u;
        while (u.endsWith("/")) u = u.substring(0, u.length() - 1);
        return u;
    }

    /** Config atual; na primeira vez migra o endereco unico do go2rtc das versoes antigas. */
    static synchronized JSONObject cfg() {
        if (cfg != null) return cfg;
        JSONObject c = null;
        try { String raw = prefs.getString("cfg", ""); if (!raw.isEmpty()) c = new JSONObject(raw); } catch (Exception ignored) { }
        if (c == null) {
            c = clean(new JSONObject());
            String old = prefs.getString("g2r", "");
            if (!old.isEmpty()) try { c.getJSONArray("servers").put(new JSONObject().put("id", "s1").put("name", "go2rtc").put("url", old).put("user", "").put("pass", "")); } catch (Exception ignored) { }
        }
        return cfg = c;
    }

    /** Normaliza o que veio de fora: so os campos conhecidos, com limites. */
    static JSONObject clean(JSONObject in) {
        JSONObject o = new JSONObject(); JSONArray servers = new JSONArray(), cams = new JSONArray(), direct = new JSONArray();
        try {
            o.put("cols", Math.max(2, Math.min(4, in.optInt("cols", 3))));
            JSONArray s = in.optJSONArray("servers"); Set<String> ids = new HashSet<String>();
            for (int i = 0; s != null && i < s.length() && i < 20; i++) {
                JSONObject j = s.optJSONObject(i); if (j == null) continue;
                String id = j.optString("id").replaceAll("[^A-Za-z0-9_-]", ""); String u = normUrl(j.optString("url"));
                if (id.isEmpty() || u.isEmpty() || !ids.add(id)) continue;
                servers.put(new JSONObject().put("id", id).put("name", lim(j.optString("name", id), 40)).put("url", u).put("user", lim(j.optString("user"), 80)).put("pass", lim(j.optString("pass"), 120)));
            }
            JSONArray d = in.optJSONArray("direct");
            for (int i = 0; d != null && i < d.length() && i < 60; i++) {
                JSONObject j = d.optJSONObject(i); if (j == null) continue;
                String id = j.optString("id").replaceAll("[^A-Za-z0-9_-]", ""); String u = j.optString("url").trim();
                if (id.isEmpty() || !u.matches("(?i)rtsps?://.+")) continue;
                direct.put(new JSONObject().put("id", id).put("name", lim(j.optString("name", id), 40)).put("url", u));
            }
            JSONArray c = in.optJSONArray("cams");
            for (int i = 0; c != null && i < c.length() && i < 400; i++) {
                JSONObject j = c.optJSONObject(i); if (j == null || j.optString("key").isEmpty()) continue;
                cams.put(new JSONObject().put("key", lim(j.optString("key"), 120)).put("name", lim(j.optString("name"), 40)).put("hidden", j.optBoolean("hidden", false)));
            }
            o.put("servers", servers).put("direct", direct).put("cams", cams);
        } catch (Exception ignored) { }
        return o;
    }

    private static String lim(String s, int n) { s = s == null ? "" : s.trim(); return s.length() > n ? s.substring(0, n) : s; }

    static synchronized void setCfg(JSONObject in) { cfg = clean(in); prefs.edit().putString("cfg", cfg.toString()).apply(); }

    static Srv server(String id) {
        JSONArray s = cfg().optJSONArray("servers");
        for (int i = 0; s != null && i < s.length(); i++) if (s.optJSONObject(i).optString("id").equals(id)) return new Srv(s.optJSONObject(i));
        return null;
    }

    // ---- rede ----

    static byte[] get(Srv s, String path, int timeoutMs) throws Exception { return http(s, "GET", path, timeoutMs); }

    static byte[] http(Srv s, String method, String path, int timeoutMs) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(s.url + path).openConnection(); c.setRequestMethod(method); c.setConnectTimeout(timeoutMs); c.setReadTimeout(timeoutMs);
        if (s.auth != null) c.setRequestProperty("Authorization", s.auth);
        int code = c.getResponseCode();
        if (code == 401 || code == 403) { c.disconnect(); throw new Exception("usuário ou senha recusados"); }
        InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream(); ByteArrayOutputStream o = new ByteArrayOutputStream(); byte[] b = new byte[16384]; int n;
        while (in != null && (n = in.read(b)) > 0) o.write(b, 0, n);
        if (in != null) in.close(); c.disconnect();
        if (code >= 400) throw new Exception("go2rtc respondeu " + code);
        return o.toByteArray();
    }

    /** Nomes das cameras de um go2rtc (GET /api/streams), ordenados. Lanca excecao se inacessivel. */
    static List<String> streams(Srv s) throws Exception {
        JSONObject j = new JSONObject(new String(get(s, "/api/streams", 4000), "UTF-8"));
        List<String> l = new ArrayList<String>(); Iterator<String> it = j.keys(); while (it.hasNext()) l.add(it.next());
        Collections.sort(l); return l;
    }

    /** Todas as cameras na ordem da config (inclui ocultas); [errors] recebe "servidor: motivo" dos servidores com falha. */
    static List<Cell> discover(Map<String, String> errors) {
        JSONObject c = cfg(); Map<String, Cell> found = new LinkedHashMap<String, Cell>();
        JSONArray servers = c.optJSONArray("servers");
        for (int i = 0; servers != null && i < servers.length(); i++) {
            Srv s = new Srv(servers.optJSONObject(i));
            try { for (String n : streams(s)) { Cell x = new Cell(); x.key = s.id + "/" + n; x.name = n; x.stream = n; x.srv = s; found.put(x.key, x); } }
            catch (Exception e) { errors.put(s.name, String.valueOf(e.getMessage() == null ? "sem resposta" : e.getMessage())); }
        }
        JSONArray direct = c.optJSONArray("direct");
        for (int i = 0; direct != null && i < direct.length(); i++) {
            JSONObject j = direct.optJSONObject(i); Cell x = new Cell(); x.key = "d:" + j.optString("id"); x.name = j.optString("name"); x.direct = j.optString("url"); found.put(x.key, x);
        }
        List<Cell> out = new ArrayList<Cell>(); JSONArray order = c.optJSONArray("cams");
        for (int i = 0; order != null && i < order.length(); i++) {
            JSONObject o = order.optJSONObject(i); Cell x = found.remove(o.optString("key")); if (x == null) continue;
            if (!o.optString("name").isEmpty()) x.name = o.optString("name");
            x.hidden = o.optBoolean("hidden", false); out.add(x);
        }
        out.addAll(found.values()); // novas: no fim, visiveis
        return out;
    }

    // ---- rotas ----

    static byte[] readBody(long len, InputStream in) throws Exception {
        if (len <= 0 || len > 256 * 1024) throw new Exception("corpo invalido");
        byte[] b = new byte[(int) len]; int off = 0, n;
        while (off < b.length && (n = in.read(b, off, b.length - off)) > 0) off += n;
        return b;
    }

    static CamServer.Resp route(String method, String path, Map<String, String> q, long len, InputStream body) throws Exception {
        if (path.equals("/")) return CamServer.Resp.html(asset("cam.html"));
        if (!path.startsWith("/api/")) return CamServer.Resp.text(404, "text/plain", "nao encontrado");
        if (!Pair.token().equals(q.get("k"))) return CamServer.Resp.text(403, "application/json", "{\"ok\":false,\"error\":\"token\"}");
        if (path.equals("/api/cfg")) {
            if (method.equals("POST")) setCfg(new JSONObject(new String(readBody(len, body), "UTF-8")));
            return CamServer.Resp.json(cfg().toString());
        }
        if (path.equals("/api/cams")) {
            Map<String, String> errors = new LinkedHashMap<String, String>(); List<Cell> l = discover(errors);
            JSONArray cams = new JSONArray(), errs = new JSONArray();
            for (Cell x : l) cams.put(new JSONObject().put("key", x.key).put("name", x.name).put("hidden", x.hidden).put("direct", x.direct != null).put("server", x.srv == null ? "" : x.srv.id).put("stream", x.stream == null ? "" : x.stream));
            for (Map.Entry<String, String> e : errors.entrySet()) errs.put(new JSONObject().put("server", e.getKey()).put("error", e.getValue()));
            return CamServer.Resp.json(new JSONObject().put("ok", true).put("cams", cams).put("errors", errs).toString());
        }
        if (path.equals("/api/add") || path.equals("/api/remove")) {
            JSONObject j = new JSONObject(new String(readBody(len, body), "UTF-8")); Srv s = server(j.optString("server"));
            if (s == null) return CamServer.Resp.json("{\"ok\":false,\"error\":\"servidor desconhecido\"}");
            String name = j.optString("name").trim(); if (name.isEmpty()) return CamServer.Resp.json("{\"ok\":false,\"error\":\"informe o nome\"}");
            if (path.equals("/api/add")) {
                String src = j.optString("src").trim();
                if (!src.matches("(?i)(rtsps?|rtmps?|https?|rtp|ffmpeg:.*|exec:.*)(://.*)?")) return CamServer.Resp.json("{\"ok\":false,\"error\":\"endereço de câmera inválido\"}");
                http(s, "PUT", "/api/streams?name=" + java.net.URLEncoder.encode(name, "UTF-8") + "&src=" + java.net.URLEncoder.encode(src, "UTF-8"), 6000);
            } else http(s, "DELETE", "/api/streams?src=" + java.net.URLEncoder.encode(name, "UTF-8"), 6000);
            return CamServer.Resp.json("{\"ok\":true}");
        }
        // compativel com a pagina web: um unico go2rtc (o primeiro servidor)
        if (path.equals("/api/set") || path.equals("/api/get")) {
            JSONObject c = cfg();
            if (path.equals("/api/set")) {
                String u = normUrl(q.get("u")); JSONArray s = c.optJSONArray("servers"); JSONArray next = new JSONArray();
                JSONObject first = s != null && s.length() > 0 ? s.optJSONObject(0) : new JSONObject().put("id", "s1").put("name", "go2rtc").put("user", "").put("pass", "");
                if (!u.isEmpty()) next.put(first.put("url", u));
                for (int i = 1; s != null && i < s.length(); i++) next.put(s.optJSONObject(i));
                setCfg(c.put("servers", next)); c = cfg();
            }
            JSONArray s = c.optJSONArray("servers"); String u = s != null && s.length() > 0 ? s.optJSONObject(0).optString("url") : "";
            StringBuilder b = new StringBuilder("{\"url\":" + q(u) + ",");
            try { List<String> l = u.isEmpty() ? new ArrayList<String>() : streams(new Srv(s.optJSONObject(0))); b.append("\"ok\":").append(!u.isEmpty()).append(",\"cams\":["); for (int i = 0; i < l.size(); i++) b.append(i > 0 ? "," : "").append(q(l.get(i))); b.append("]}"); }
            catch (Exception e) { b.append("\"ok\":false,\"cams\":[],\"error\":").append(q(u.isEmpty() ? "informe o endereço" : "não consegui falar com o go2rtc")).append("}"); }
            return CamServer.Resp.json(b.toString());
        }
        return CamServer.Resp.text(404, "application/json", "{\"ok\":false}");
    }
}
