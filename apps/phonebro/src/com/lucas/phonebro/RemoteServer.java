package com.lucas.phonebro;

import java.io.*;
import java.net.*;
import java.util.*;

/** Servidor HTTP minimo (um thread por conexao, Connection: close). */
class RemoteServer extends Thread {
    interface Handler { Response handle(String path, Map<String, String> query); }

    static class Response {
        final int status; final String type; final byte[] body;
        Response(int status, String type, byte[] body) { this.status = status; this.type = type; this.body = body; }
        static Response html(String s) { return utf8(200, "text/html; charset=utf-8", s); }
        static Response json(String s) { return utf8(200, "application/json; charset=utf-8", s); }
        static Response utf8(int st, String type, String s) { try { return new Response(st, type, s.getBytes("UTF-8")); } catch (UnsupportedEncodingException e) { throw new RuntimeException(e); } }
    }

    private int port; private final Handler handler; private volatile boolean running = true; private ServerSocket server;

    RemoteServer(Handler handler) { super("remote-server"); this.handler = handler; setDaemon(true); }

    /** Tenta a porta preferida, depois 8765..8805 e por fim qualquer porta livre. Retorna a porta escolhida. */
    int bind(int preferred) throws IOException {
        List<Integer> candidates = new ArrayList<Integer>();
        if (preferred > 0) candidates.add(preferred);
        for (int p = 8765; p <= 8805; p++) if (p != preferred) candidates.add(p);
        candidates.add(0);
        for (int p : candidates) {
            try {
                ServerSocket ss = new ServerSocket();
                ss.setReuseAddress(true);
                ss.bind(new InetSocketAddress(p));
                server = ss; port = ss.getLocalPort();
                return port;
            } catch (IOException busy) { /* proxima */ }
        }
        throw new IOException("nenhuma porta livre");
    }

    @Override public void run() {
        try {
            while (running) {
                final Socket s = server.accept();
                new Thread(new Runnable() { public void run() { serve(s); } }).start();
            }
        } catch (IOException ignored) { }
    }

    void shutdown() { running = false; try { if (server != null) server.close(); } catch (IOException ignored) { } }

    private void serve(Socket s) {
        try {
            s.setSoTimeout(5000);
            BufferedReader in = new BufferedReader(new InputStreamReader(s.getInputStream(), "ISO-8859-1"));
            String line = in.readLine();
            if (line == null) return;
            String h; while ((h = in.readLine()) != null && h.length() > 0) { }
            String[] p = line.split(" ");
            String target = p.length > 1 ? p[1] : "/";
            String path = target; Map<String, String> q = new HashMap<String, String>();
            int i = target.indexOf('?');
            if (i >= 0) {
                path = target.substring(0, i);
                for (String kv : target.substring(i + 1).split("&")) {
                    int e = kv.indexOf('=');
                    if (e > 0) q.put(URLDecoder.decode(kv.substring(0, e), "UTF-8"), URLDecoder.decode(kv.substring(e + 1), "UTF-8"));
                }
            }
            Response r;
            try { r = handler.handle(path, q); } catch (Throwable ex) { r = Response.utf8(500, "text/plain", String.valueOf(ex)); }
            OutputStream out = s.getOutputStream();
            String head = "HTTP/1.1 " + r.status + " X\r\nContent-Type: " + r.type + "\r\nContent-Length: " + r.body.length
                    + "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
            out.write(head.getBytes("ISO-8859-1")); out.write(r.body); out.flush();
        } catch (Throwable ex) { android.util.Log.e("PhoneBro", "serve", ex);
        } finally { try { s.close(); } catch (IOException ignored) { } }
    }
}
