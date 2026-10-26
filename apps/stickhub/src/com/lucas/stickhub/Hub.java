package com.lucas.stickhub;

import android.app.ActivityManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.Build;
import android.os.Debug;
import android.os.Environment;
import android.os.StatFs;
import android.os.SystemClock;
import android.provider.Settings;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.*;

/** Estado global + rotas da API. Roda em qualquer processo/Context (usa applicationContext). */
final class Hub {
    static final String ACTION_INSTALL = "com.lucas.stickhub.INSTALL_RESULT";
    static volatile String url = "", token = "", installStatus = "";
    static volatile int port;
    private static Context app; private static HubServer server;

    static synchronized void ensureStarted(Context ctx) {
        if (server != null) return;
        app = ctx.getApplicationContext();
        SharedPreferences p = app.getSharedPreferences("hub", Context.MODE_PRIVATE);
        token = p.getString("token", null);
        if (token == null) { token = UUID.randomUUID().toString().substring(0, 8); p.edit().putString("token", token).apply(); }
        HubServer s = new HubServer(new HubServer.Handler() {
            public HubServer.Resp handle(String m, String path, Map<String, String> q, long len, InputStream body) throws Exception { return route(m, path, q, len, body); }
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

    // ---------- Rotas ----------
    private static HubServer.Resp route(String method, String path, Map<String, String> q, long len, InputStream body) throws Exception {
        if (path.equals("/")) return HubServer.Resp.html(asset("hub.html"));
        if (!path.startsWith("/api/") || !token.equals(q.get("k"))) return HubServer.Resp.text(403, "text/plain", "forbidden");
        String cmd = path.substring(5), pkg = q.get("pkg");
        if (cmd.equals("info")) return HubServer.Resp.json(info());
        if (cmd.equals("apps")) return HubServer.Resp.json(apps());
        if (cmd.equals("icon")) return icon(pkg);
        if (cmd.equals("installstatus")) return HubServer.Resp.json("{\"status\":" + q(installStatus) + "}");
        if (cmd.equals("install")) return install(q.get("name"), len, body);
        PackageManager pm = app.getPackageManager();
        if (cmd.equals("launch")) {
            Intent i = pm.getLeanbackLaunchIntentForPackage(pkg); if (i == null) i = pm.getLaunchIntentForPackage(pkg);
            if (i == null) return ok(false, "sem tela de abertura");
            app.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return ok(true, "");
        }
        if (cmd.equals("stop")) { ((ActivityManager) app.getSystemService(Context.ACTIVITY_SERVICE)).killBackgroundProcesses(pkg); return ok(true, ""); }
        if (cmd.equals("uninstall")) { app.startActivity(new Intent(Intent.ACTION_DELETE, Uri.parse("package:" + pkg)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return ok(true, "Confirme na TV"); }
        if (cmd.equals("details")) { app.startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + pkg)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return ok(true, ""); }
        if (cmd.equals("clean")) return HubServer.Resp.json(clean());
        if (cmd.equals("openurl")) {
            Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(q.get("url"))).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try { pm.getPackageInfo("com.lucas.phonebro", 0); i.setPackage("com.lucas.phonebro"); } catch (PackageManager.NameNotFoundException ignored) { }
            app.startActivity(i); return ok(true, "");
        }
        return HubServer.Resp.text(404, "text/plain", "?");
    }

    private static HubServer.Resp ok(boolean ok, String msg) { return HubServer.Resp.json("{\"ok\":" + ok + ",\"msg\":" + q(msg) + "}"); }

    private static String asset(String name) throws Exception {
        InputStream in = app.getAssets().open(name); ByteArrayOutputStream o = new ByteArrayOutputStream(); byte[] b = new byte[8192]; int n;
        while ((n = in.read(b)) > 0) o.write(b, 0, n); in.close(); return o.toString("UTF-8");
    }

    // ---------- Sistema ----------
    static long freeRam() { ActivityManager am = (ActivityManager) app.getSystemService(Context.ACTIVITY_SERVICE); ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo(); am.getMemoryInfo(mi); return mi.availMem; }

    static String info() {
        ActivityManager am = (ActivityManager) app.getSystemService(Context.ACTIVITY_SERVICE); ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo(); am.getMemoryInfo(mi);
        StatFs fs = new StatFs(Environment.getDataDirectory().getPath());
        StringBuilder top = new StringBuilder("[");
        try {
            PackageManager pm = app.getPackageManager(); Map<String, Integer> byPkg = new HashMap<String, Integer>();
            List<ActivityManager.RunningAppProcessInfo> ps = am.getRunningAppProcesses();
            if (ps != null) for (ActivityManager.RunningAppProcessInfo p : ps) {
                Debug.MemoryInfo[] m = am.getProcessMemoryInfo(new int[]{p.pid});
                int kb = m != null && m.length > 0 ? m[0].getTotalPss() : 0; if (kb <= 0) continue;
                String name = p.pkgList != null && p.pkgList.length > 0 ? p.pkgList[0] : p.processName;
                Integer old = byPkg.get(name); byPkg.put(name, (old == null ? 0 : old) + kb);
            }
            List<Map.Entry<String, Integer>> list = new ArrayList<Map.Entry<String, Integer>>(byPkg.entrySet());
            Collections.sort(list, new Comparator<Map.Entry<String, Integer>>() { public int compare(Map.Entry<String, Integer> a, Map.Entry<String, Integer> b) { return b.getValue() - a.getValue(); } });
            for (int i = 0; i < Math.min(8, list.size()); i++) {
                String label = list.get(i).getKey(); try { label = String.valueOf(pm.getApplicationLabel(pm.getApplicationInfo(label, 0))); } catch (Exception ignored) { }
                top.append(i > 0 ? "," : "").append("{\"pkg\":").append(q(list.get(i).getKey())).append(",\"label\":").append(q(label)).append(",\"mb\":").append(list.get(i).getValue() / 1024).append("}");
            }
        } catch (Throwable ignored) { }
        top.append("]");
        return "{\"model\":" + q(Build.MANUFACTURER + " " + Build.MODEL) + ",\"android\":" + q(Build.VERSION.RELEASE) + ",\"sdk\":" + Build.VERSION.SDK_INT
                + ",\"ramTotal\":" + (mi.totalMem >> 20) + ",\"ramFree\":" + (mi.availMem >> 20)
                + ",\"diskTotal\":" + (fs.getTotalBytes() >> 20) + ",\"diskFree\":" + (fs.getAvailableBytes() >> 20)
                + ",\"uptime\":" + (SystemClock.elapsedRealtime() / 1000) + ",\"top\":" + top + "}";
    }

    static String clean() {
        ActivityManager am = (ActivityManager) app.getSystemService(Context.ACTIVITY_SERVICE); long before = freeRam();
        for (ApplicationInfo ai : app.getPackageManager().getInstalledApplications(0))
            if (!ai.packageName.equals(app.getPackageName()) && !ai.packageName.equals("com.lucas.phonebro") && !ai.packageName.equals("com.lucas.firehome")) am.killBackgroundProcesses(ai.packageName);
        try { Thread.sleep(1200); } catch (InterruptedException ignored) { }
        return "{\"before\":" + (before >> 20) + ",\"after\":" + (freeRam() >> 20) + "}";
    }

    // ---------- Apps ----------
    private static String apps() {
        PackageManager pm = app.getPackageManager(); StringBuilder b = new StringBuilder("[");
        boolean first = true;
        for (ApplicationInfo ai : pm.getInstalledApplications(0)) {
            boolean launch = pm.getLeanbackLaunchIntentForPackage(ai.packageName) != null || pm.getLaunchIntentForPackage(ai.packageName) != null;
            boolean sys = (ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0 && (ai.flags & ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0;
            if (!launch && sys) continue;
            String ver = ""; try { ver = pm.getPackageInfo(ai.packageName, 0).versionName; } catch (Exception ignored) { }
            b.append(first ? "" : ",").append("{\"pkg\":").append(q(ai.packageName)).append(",\"label\":").append(q(String.valueOf(pm.getApplicationLabel(ai))))
                    .append(",\"sys\":").append(sys).append(",\"launch\":").append(launch).append(",\"ver\":").append(q(ver == null ? "" : ver)).append("}");
            first = false;
        }
        return b.append("]").toString();
    }

    private static HubServer.Resp icon(String pkg) throws Exception {
        Drawable d = app.getPackageManager().getApplicationIcon(pkg);
        Bitmap bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888); Canvas c = new Canvas(bmp); d.setBounds(0, 0, 96, 96); d.draw(c);
        ByteArrayOutputStream o = new ByteArrayOutputStream(); bmp.compress(Bitmap.CompressFormat.PNG, 100, o);
        return new HubServer.Resp(200, "image/png", o.toByteArray(), "max-age=3600");
    }

    // ---------- Instalar APK enviado pelo celular ----------
    private static HubServer.Resp install(String name, long len, InputStream body) throws Exception {
        if (len <= 0) return ok(false, "arquivo vazio");
        PackageInstaller pi = app.getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams sp = new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        int id = pi.createSession(sp); PackageInstaller.Session s = pi.openSession(id);
        try {
            OutputStream out = s.openWrite(name == null ? "app.apk" : name, 0, len);
            byte[] buf = new byte[65536]; long left = len; int n;
            while (left > 0 && (n = body.read(buf, 0, (int) Math.min(buf.length, left))) > 0) { out.write(buf, 0, n); left -= n; }
            s.fsync(out); out.close();
            if (left > 0) { s.abandon(); return ok(false, "upload incompleto"); }
            installStatus = "aguardando confirmacao na TV";
            Intent cb = new Intent(ACTION_INSTALL).setPackage(app.getPackageName());
            int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0);
            s.commit(PendingIntent.getBroadcast(app, id, cb, flags).getIntentSender());
        } catch (Exception e) { s.abandon(); throw e; }
        return ok(true, "Confirme a instalacao na TV");
    }
}
