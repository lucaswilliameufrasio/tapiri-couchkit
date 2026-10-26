package com.lucas.stickhub;

import java.io.*;
import java.net.*;
import java.util.*;

/** Servidor HTTP minimo com suporte a corpo (upload de APK). Um thread por conexao. */
class HubServer extends Thread {
    interface Handler { Resp handle(String method, String path, Map<String, String> q, long contentLength, InputStream body) throws Exception; }

    static class Resp {
        final int status; final String type; final byte[] body; final String cache;
        Resp(int status, String type, byte[] body, String cache) { this.status = status; this.type = type; this.body = body; this.cache = cache; }
        static Resp text(int st, String type, String s) { try { return new Resp(st, type, s.getBytes("UTF-8"), "no-store"); } catch (UnsupportedEncodingException e) { throw new RuntimeException(e); } }
        static Resp html(String s) { return text(200, "text/html; charset=utf-8", s); }
        static Resp json(String s) { return text(200, "application/json; charset=utf-8", s); }
    }

    private final Handler handler; private ServerSocket server; private volatile boolean running = true;

    HubServer(Handler h) { super("hub-server"); handler = h; setDaemon(true); }

    int bind(int preferred) throws IOException {
        List<Integer> c = new ArrayList<Integer>();
        if (preferred > 0) c.add(preferred);
        for (int p = 8800; p <= 8840; p++) if (p != preferred) c.add(p);
        c.add(0);
        for (int p : c) {
            try { ServerSocket s = new ServerSocket(); s.setReuseAddress(true); s.bind(new InetSocketAddress(p)); server = s; return s.getLocalPort(); }
            catch (IOException busy) { }
        }
        throw new IOException("sem porta livre");
    }

    @Override public void run() {
        try { while (running) { final Socket s = server.accept(); new Thread(new Runnable() { public void run() { serve(s); } }).start(); } }
        catch (IOException ignored) { }
    }

    void shutdown() { running = false; try { if (server != null) server.close(); } catch (IOException ignored) { } }

    private static String line(InputStream in) throws IOException {
        StringBuilder b = new StringBuilder(); int c;
        while ((c = in.read()) != -1 && c != '\n') if (c != '\r') b.append((char) c);
        return c == -1 && b.length() == 0 ? null : b.toString();
    }

    private void serve(Socket s) {
        try {
            s.setSoTimeout(60000);
            InputStream in = new BufferedInputStream(s.getInputStream(), 16384);
            String req = line(in); if (req == null) return;
            long len = 0; String h;
            while ((h = line(in)) != null && h.length() > 0) if (h.toLowerCase(Locale.ROOT).startsWith("content-length:")) len = Long.parseLong(h.substring(15).trim());
            String[] p = req.split(" "); String method = p[0], target = p.length > 1 ? p[1] : "/", path = target;
            Map<String, String> q = new HashMap<String, String>();
            int i = target.indexOf('?');
            if (i >= 0) {
                path = target.substring(0, i);
                for (String kv : target.substring(i + 1).split("&")) { int e = kv.indexOf('='); if (e > 0) q.put(URLDecoder.decode(kv.substring(0, e), "UTF-8"), URLDecoder.decode(kv.substring(e + 1), "UTF-8")); }
            }
            Resp r;
            try { r = handler.handle(method, path, q, len, in); } catch (Throwable ex) { r = Resp.text(500, "application/json", "{\"ok\":false,\"error\":" + Hub.q(String.valueOf(ex.getMessage())) + "}"); }
            OutputStream out = s.getOutputStream();
            out.write(("HTTP/1.1 " + r.status + " X\r\nContent-Type: " + r.type + "\r\nContent-Length: " + r.body.length + "\r\nCache-Control: " + r.cache + "\r\nConnection: close\r\n\r\n").getBytes("ISO-8859-1"));
            out.write(r.body); out.flush();
        } catch (Throwable ignored) {
        } finally { try { s.close(); } catch (IOException ignored) { } }
    }
}
