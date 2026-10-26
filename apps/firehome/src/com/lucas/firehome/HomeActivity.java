package com.lucas.firehome;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;
import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.*;

public class HomeActivity extends Activity {
    private static final String SETTINGS_PKG = "com.amazon.tv.settings.v2";
    private static HomeActivity inst;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private PackageManager pm;
    private float dp;
    private FrameLayout root, qrOverlay; private ImageView wall, qrImg; private TextView qrAddr; private View dim;
    private LinearLayout content, colDate;
    private TextView clock, date, greeting, weather, mem, hint;
    private JSONObject conf = new JSONObject();
    private int accent = 0xFF5CC8FF; private float scale = 1f; private int radius = 14, labelSize = 14;
    private long wallStamp = -1; private Bitmap wallBmp;
    private final Runnable tick = new Runnable() { public void run() { updateClock(); ui.postDelayed(this, 15000); } };

    private static class Item {
        String label, glyph; Drawable img; boolean banner; Intent intent; Runnable action; String pkg;
    }

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        pm = getPackageManager(); dp = getResources().getDisplayMetrics().density;
        Cfg.ensureStarted(this);
        try { Intent s = new Intent(this, ConfigService.class); if (Build.VERSION.SDK_INT >= 26) startForegroundService(s); else startService(s); } catch (Exception ignored) { }

        root = new FrameLayout(this);
        wall = new ImageView(this); wall.setScaleType(ImageView.ScaleType.CENTER_CROP); wall.setVisibility(View.GONE);
        root.addView(wall, new FrameLayout.LayoutParams(-1, -1));
        dim = new View(this); dim.setVisibility(View.GONE); root.addView(dim, new FrameLayout.LayoutParams(-1, -1));

        LinearLayout page = new LinearLayout(this); page.setOrientation(LinearLayout.VERTICAL);
        LinearLayout top = new LinearLayout(this); top.setGravity(Gravity.CENTER_VERTICAL); top.setPadding(px(56), px(32), px(56), 0);
        clock = text(52, Color.WHITE, true);
        colDate = new LinearLayout(this); colDate.setOrientation(LinearLayout.VERTICAL); colDate.setPadding(px(18), px(14), 0, 0);
        date = text(18, 0xAAFFFFFF, false); greeting = text(16, 0xCCFFFFFF, true);
        colDate.addView(date); colDate.addView(greeting);
        weather = text(18, 0xCCFFFFFF, true); weather.setGravity(Gravity.RIGHT); weather.setPadding(0, 0, px(24), 0);
        mem = text(16, 0x88FFFFFF, false); mem.setGravity(Gravity.RIGHT);
        top.addView(clock); top.addView(colDate);
        View sp = new View(this); top.addView(sp, new LinearLayout.LayoutParams(0, 1, 1));
        top.addView(weather); top.addView(mem);
        page.addView(top);

        ScrollView sv = new ScrollView(this); sv.setFillViewport(false); sv.setClipChildren(false); sv.setVerticalScrollBarEnabled(false);
        content = new LinearLayout(this); content.setOrientation(LinearLayout.VERTICAL); content.setPadding(0, px(8), 0, px(16)); content.setClipChildren(false); content.setClipToPadding(false);
        sv.addView(content); page.addView(sv, new LinearLayout.LayoutParams(-1, 0, 1));
        root.addView(page, new FrameLayout.LayoutParams(-1, -1));
        hint = text(14, 0x99FFFFFF, false); hint.setText("OK abrir   ·   segure OK para fixar ou remover dos favoritos   ·   MENU personalizar pelo celular"); hint.setGravity(Gravity.CENTER);
        hint.setPadding(0, px(8), 0, px(14)); hint.setBackgroundColor(0x55000000);
        page.addView(hint, new LinearLayout.LayoutParams(-1, -2));
        buildQrOverlay();
        setContentView(root);
    }

    @Override protected void onResume() { super.onResume(); inst = this; build(); ui.post(tick); }
    @Override protected void onPause() { super.onPause(); if (inst == this) inst = null; ui.removeCallbacks(tick); }
    @Override protected void onNewIntent(Intent i) { super.onNewIntent(i); if (content != null && content.getChildCount() > 0) content.requestFocus(); }

    @Override public void onBackPressed() { if (qrOverlay.getVisibility() == View.VISIBLE) qrOverlay.setVisibility(View.GONE); /* launcher: nao sai */ }

    @Override public boolean onKeyDown(int k, KeyEvent e) {
        if (k == KeyEvent.KEYCODE_MENU) { toggleQr(); return true; }
        return super.onKeyDown(k, e);
    }

    /** Chamado pelo servidor quando a configuracao muda. */
    static void refresh() {
        final HomeActivity a = inst; if (a == null) return;
        a.runOnUiThread(new Runnable() { public void run() { a.build(); a.updateClock(); } });
    }

    static byte[] snapshotJpeg() throws Exception { HomeActivity a = inst; return a == null ? null : Cfg.drawToJpeg(a.root, a); }

    private int px(float v) { return (int) (v * dp + 0.5f); }

    private TextView text(int sp, int color, boolean bold) {
        TextView t = new TextView(this); t.setTextSize(sp); t.setTextColor(color); t.setSingleLine(true);
        if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT_BOLD); return t;
    }

    private static int col(String s, int def) { try { return Color.parseColor(s); } catch (Exception e) { return def; } }

    // ---------- Configuracao -> visual ----------
    private void applyConfig() {
        JSONObject th = conf.optJSONObject("theme"), wp = conf.optJSONObject("wallpaper"), hd = conf.optJSONObject("header");
        if (th == null) th = new JSONObject(); if (wp == null) wp = new JSONObject(); if (hd == null) hd = new JSONObject();
        JSONArray bg = th.optJSONArray("bg"); int[] c = {0xFF0B1020, 0xFF1B1140, 0xFF3A1550};
        for (int i = 0; i < 3 && bg != null; i++) c[i] = col(bg.optString(Math.min(i, Math.max(0, bg.length() - 1)), ""), c[i]);
        root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR, c));
        accent = col(th.optString("accent", "#5CC8FF"), 0xFF5CC8FF);
        scale = Math.max(0.6f, Math.min(1.5f, (float) th.optDouble("scale", 100) / 100f));
        radius = (int) Math.max(0, Math.min(40, th.optDouble("radius", 14))); labelSize = (int) Math.max(10, Math.min(24, th.optDouble("labelSize", 14)));

        java.io.File wf = Cfg.wallpaperFile(); boolean useWall = wp.optBoolean("on", false) && wf.exists();
        if (useWall) {
            if (wallBmp == null || wallStamp != wf.lastModified()) {
                try { wallBmp = BitmapFactory.decodeFile(wf.getAbsolutePath()); wallStamp = wf.lastModified(); } catch (Throwable t) { wallBmp = null; }
            }
            useWall = wallBmp != null; if (useWall) wall.setImageBitmap(wallBmp);
        }
        wall.setVisibility(useWall ? View.VISIBLE : View.GONE);
        dim.setVisibility(useWall ? View.VISIBLE : View.GONE);
        dim.setBackgroundColor((Math.min(90, Math.max(0, wp.optInt("dim", 55))) * 255 / 100) << 24);

        clock.setVisibility(hd.optBoolean("clock", true) ? View.VISIBLE : View.GONE);
        date.setVisibility(hd.optBoolean("date", true) ? View.VISIBLE : View.GONE);
        String g = hd.optString("greeting", ""); greeting.setText(g); greeting.setVisibility(g.isEmpty() ? View.GONE : View.VISIBLE);
        colDate.setVisibility(date.getVisibility() == View.VISIBLE || !g.isEmpty() ? View.VISIBLE : View.GONE);
        mem.setVisibility(hd.optBoolean("ram", true) ? View.VISIBLE : View.GONE);
        hint.setVisibility(conf.optBoolean("hint", true) ? View.VISIBLE : View.GONE);
    }

    private void updateClock() {
        JSONObject hd = conf.optJSONObject("header"); boolean h24 = hd == null || hd.optBoolean("h24", true);
        Date now = new Date();
        clock.setText(new SimpleDateFormat(h24 ? "HH:mm" : "h:mm a", Locale.getDefault()).format(now));
        date.setText(new SimpleDateFormat("EEEE, d 'de' MMMM", new Locale("pt", "BR")).format(now));
        ActivityManager am = (ActivityManager) getSystemService(ACTIVITY_SERVICE); ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
        am.getMemoryInfo(mi); mem.setText("RAM livre " + (mi.availMem >> 20) + " MB");
        Cfg.updateWeather(); weather.setText(Cfg.weather); weather.setVisibility(Cfg.weather.isEmpty() ? View.GONE : View.VISIBLE);
    }

    // ---------- Dados ----------
    private static Set<String> set(JSONArray a) { Set<String> s = new HashSet<String>(); for (int i = 0; a != null && i < a.length(); i++) s.add(a.optString(i)); return s; }

    private List<Item> installedApps() {
        Set<String> hiddenPkg = set(conf.optJSONArray("hidden")); JSONArray hl = conf.optJSONArray("hideLabels"); JSONObject names = conf.optJSONObject("names");
        Map<String, Item> map = new LinkedHashMap<String, Item>();
        for (int pass = 0; pass < 2; pass++) {
            Intent q = new Intent(Intent.ACTION_MAIN).addCategory(pass == 0 ? Intent.CATEGORY_LEANBACK_LAUNCHER : Intent.CATEGORY_LAUNCHER);
            for (ResolveInfo ri : pm.queryIntentActivities(q, 0)) {
                String pkg = ri.activityInfo.packageName;
                if (pkg.equals(getPackageName()) || pkg.equals(SETTINGS_PKG) || map.containsKey(pkg) || hiddenPkg.contains(pkg)) continue;
                if (pass == 1 && (ri.activityInfo.applicationInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0) continue;
                String lbl = String.valueOf(ri.loadLabel(pm)); if (hiddenLabel(hl, lbl)) continue;
                Item it = new Item(); it.pkg = pkg; it.label = names != null && names.optString(pkg, "").length() > 0 ? names.optString(pkg) : lbl;
                Drawable banner = null; try { banner = pm.getApplicationBanner(pkg); } catch (Exception ignored) { }
                if (banner == null) try { banner = ri.activityInfo.loadBanner(pm); } catch (Exception ignored) { }
                it.banner = banner != null; it.img = banner != null ? banner : ri.loadIcon(pm);
                it.intent = new Intent(Intent.ACTION_MAIN).addCategory(pass == 0 ? Intent.CATEGORY_LEANBACK_LAUNCHER : Intent.CATEGORY_LAUNCHER)
                        .setClassName(pkg, ri.activityInfo.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
                map.put(pkg, it);
            }
        }
        return new ArrayList<Item>(map.values());
    }

    private static boolean hiddenLabel(JSONArray hl, String l) { for (int i = 0; hl != null && i < hl.length(); i++) { String h = hl.optString(i); if (!h.isEmpty() && l.contains(h)) return true; } return false; }

    private void togglePin(String pkg) {
        try {
            JSONObject c = Cfg.snapshot(); JSONArray pins = c.optJSONArray("pins"), out = new JSONArray(); boolean found = false;
            for (int i = 0; pins != null && i < pins.length(); i++) { if (pkg.equals(pins.optString(i))) found = true; else out.put(pins.optString(i)); }
            if (!found) out.put(pkg);
            c.put("pins", out); Cfg.save(c);
            Toast.makeText(this, "Favoritos atualizados", Toast.LENGTH_SHORT).show();
        } catch (Exception e) { Toast.makeText(this, "Não foi possível salvar", Toast.LENGTH_SHORT).show(); }
    }

    private Item tool(String label, String glyph, Runnable r, Intent i) {
        Item it = new Item(); it.label = label; it.action = r; it.intent = i;
        GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{0xFF3A4A9A, 0xFF7A3AA0}); it.img = g; it.glyph = glyph; return it;
    }

    private Item toolById(String id) {
        if (id.equals("settings")) return tool("Configurações", "gear", null, settingsIntent());
        if (id.equals("clean")) return tool("Limpar RAM", "bolt", new Runnable() { public void run() { cleanRam(); } }, null);
        if (id.equals("wifi")) return tool("Rede", "wifi", null, new Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        if (id.equals("customize")) return tool("Personalizar", "gear", new Runnable() { public void run() { toggleQr(); } }, null);
        return null;
    }

    // ---------- UI ----------
    private void build() {
        conf = Cfg.snapshot(); applyConfig();
        content.removeAllViews();
        List<Item> all = installedApps(); Map<String, Item> byPkg = new HashMap<String, Item>(); for (Item i : all) byPkg.put(i.pkg, i);
        JSONArray pinArr = conf.optJSONArray("pins"); List<String> pins = new ArrayList<String>();
        for (int i = 0; pinArr != null && i < pinArr.length(); i++) pins.add(pinArr.optString(i));
        content.addView(spacer());
        JSONArray rows = conf.optJSONArray("rows");
        for (int r = 0; rows != null && r < rows.length(); r++) {
            JSONObject row = rows.optJSONObject(r); if (row == null || !row.optBoolean("show", true)) continue;
            String type = row.optString("type", ""); List<Item> items = new ArrayList<Item>();
            if (type.equals("pins")) { for (String p : pins) if (byPkg.containsKey(p)) items.add(byPkg.get(p)); }
            else if (type.equals("all")) {
                for (Item i : all) if (!pins.contains(i.pkg)) items.add(i);
                Collections.sort(items, new Comparator<Item>() { public int compare(Item a, Item b) { return a.label.compareToIgnoreCase(b.label); } });
            } else if (type.equals("custom")) {
                JSONArray a = row.optJSONArray("apps"); for (int i = 0; a != null && i < a.length(); i++) if (byPkg.containsKey(a.optString(i))) items.add(byPkg.get(a.optString(i)));
            } else if (type.equals("tools")) {
                JSONArray t = conf.optJSONArray("tools"); for (int i = 0; t != null && i < t.length(); i++) { Item it = toolById(t.optString(i)); if (it != null) items.add(it); }
            }
            addRow(row.optString("title", ""), items, row.optBoolean("big", false));
        }
        content.post(new Runnable() { public void run() { content.requestFocus(); } });
    }

    private View spacer() { View v = new View(this); v.setLayoutParams(new LinearLayout.LayoutParams(1, px(4))); return v; }

    private Intent settingsIntent() {
        Intent i = pm.getLaunchIntentForPackage(SETTINGS_PKG);
        if (i == null) i = new Intent(Settings.ACTION_SETTINGS);
        return i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }

    private void addRow(String title, List<Item> items, boolean big) {
        if (items.isEmpty()) return;
        TextView h = text(18, 0xCCFFFFFF, true); h.setText(title); h.setPadding(px(56), px(20), 0, px(8)); content.addView(h);
        HorizontalScrollView hs = new HorizontalScrollView(this); hs.setHorizontalScrollBarEnabled(false); hs.setClipToPadding(false);
        LinearLayout row = new LinearLayout(this); row.setPadding(px(44), px(12), px(44), px(24)); row.setClipChildren(false); hs.setClipChildren(false); hs.setClipToPadding(false); hs.addView(row);
        for (Item it : items) row.addView(card(it, big));
        content.addView(hs, new LinearLayout.LayoutParams(-1, -2));
    }

    private View card(final Item it, boolean big) {
        final int ring = px(8), w = px((big ? 232 : 180) * scale), h = px((big ? 130 : 101) * scale), rad = px(radius);
        LinearLayout c = new LinearLayout(this); c.setOrientation(LinearLayout.VERTICAL); c.setGravity(Gravity.CENTER_HORIZONTAL);
        LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(w + 2 * ring, -2); clp.setMargins(px(6), 0, px(6), 0); c.setLayoutParams(clp);
        c.setFocusable(true); c.setClickable(true);
        c.setContentDescription(it.label);

        // anel de foco: fica FORA do container recortado, entao nunca e cortado
        final GradientDrawable focusRing = new GradientDrawable(); focusRing.setCornerRadius(rad + px(4)); focusRing.setColor(Color.TRANSPARENT);
        FrameLayout ringBox = new FrameLayout(this); ringBox.setPadding(ring, ring, ring, ring); ringBox.setBackground(new android.graphics.drawable.InsetDrawable(focusRing, px(2)));

        FrameLayout box = new FrameLayout(this);
        GradientDrawable shape = new GradientDrawable(); shape.setCornerRadius(rad); shape.setColor(0x22FFFFFF); box.setBackground(shape);
        box.setClipToOutline(true);
        box.setOutlineProvider(new android.view.ViewOutlineProvider() { public void getOutline(View v, android.graphics.Outline o) { o.setRoundRect(0, 0, v.getWidth(), v.getHeight(), rad); } });
        if (it.glyph != null) {
            box.setBackground(it.img);
            ImageView g = new ImageView(this); g.setImageDrawable(new GlyphDrawable(it.glyph)); int gp = px(34); g.setPadding(gp, gp / 2, gp, gp / 2);
            box.addView(g, new FrameLayout.LayoutParams(-1, -1));
        } else {
            ImageView iv = new ImageView(this); iv.setImageDrawable(it.img);
            iv.setScaleType(it.banner ? ImageView.ScaleType.CENTER_CROP : ImageView.ScaleType.FIT_CENTER);
            int pad = it.banner ? 0 : px(18); iv.setPadding(pad, pad, pad, pad); box.addView(iv, new FrameLayout.LayoutParams(-1, -1));
        }
        ringBox.addView(box, new FrameLayout.LayoutParams(w, h));
        c.addView(ringBox, new LinearLayout.LayoutParams(w + 2 * ring, h + 2 * ring));

        TextView l = text(labelSize, Color.WHITE, false); l.setSingleLine(false); l.setMaxLines(2); l.setMinLines(2); l.setText(it.label);
        l.setGravity(Gravity.CENTER_HORIZONTAL | Gravity.TOP); l.setPadding(px(4), px(6), px(4), 0); l.setAlpha(0.78f);
        l.setEllipsize(android.text.TextUtils.TruncateAt.END); c.addView(l, new LinearLayout.LayoutParams(w + 2 * ring, -2));

        c.setOnFocusChangeListener(new View.OnFocusChangeListener() {
            public void onFocusChange(View v, boolean has) {
                v.setElevation(has ? px(12) : 0);
                focusRing.setStroke(px(3), has ? accent : Color.TRANSPARENT);
                ((ViewGroup) v).getChildAt(1).setAlpha(has ? 1f : 0.78f);
            }
        });
        c.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { launch(it); } });
        if (it.pkg != null) c.setOnLongClickListener(new View.OnLongClickListener() { public boolean onLongClick(View v) { togglePin(it.pkg); return true; } });
        return c;
    }

    private void launch(Item it) {
        try { if (it.action != null) it.action.run(); else startActivity(it.intent); }
        catch (Exception e) { Toast.makeText(this, "Não foi possível abrir " + it.label, Toast.LENGTH_SHORT).show(); }
    }

    private void cleanRam() {
        ActivityManager am = (ActivityManager) getSystemService(ACTIVITY_SERVICE); ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
        am.getMemoryInfo(mi); long before = mi.availMem;
        for (ApplicationInfo ai : pm.getInstalledApplications(0)) if (!ai.packageName.equals(getPackageName())) am.killBackgroundProcesses(ai.packageName);
        ui.postDelayed(new Runnable() { public void run() {
            ActivityManager a = (ActivityManager) getSystemService(ACTIVITY_SERVICE); ActivityManager.MemoryInfo m = new ActivityManager.MemoryInfo(); a.getMemoryInfo(m);
            Toast.makeText(HomeActivity.this, "RAM livre: " + (m.availMem >> 20) + " MB (antes " + (before >> 20) + " MB)", Toast.LENGTH_LONG).show(); updateClock();
        } }, 1200);
    }

    // ---------- QR para personalizar pelo celular ----------
    private void buildQrOverlay() {
        qrOverlay = new FrameLayout(this); qrOverlay.setBackgroundColor(0xCC000000); qrOverlay.setVisibility(View.GONE); qrOverlay.setClickable(true);
        LinearLayout box = new LinearLayout(this); box.setOrientation(LinearLayout.VERTICAL); box.setGravity(Gravity.CENTER_HORIZONTAL); box.setPadding(px(32), px(28), px(32), px(24));
        GradientDrawable bg = new GradientDrawable(); bg.setColor(0xFF1B1530); bg.setCornerRadius(px(22)); box.setBackground(bg);
        TextView t = text(24, Color.WHITE, true); t.setText("Personalize pelo celular"); box.addView(t);
        final ImageView qr = qrImg = new ImageView(this); GradientDrawable qbg = new GradientDrawable(); qbg.setColor(Color.WHITE); qbg.setCornerRadius(px(14)); qr.setBackground(qbg); qr.setPadding(px(10), px(10), px(10), px(10));
        LinearLayout.LayoutParams qp = new LinearLayout.LayoutParams(px(230), px(230)); qp.setMargins(0, px(16), 0, px(12)); box.addView(qr, qp);
        final TextView addr = qrAddr = text(15, 0xFF9FD8FF, true); addr.setSingleLine(false); addr.setGravity(Gravity.CENTER); box.addView(addr, new LinearLayout.LayoutParams(px(520), -2));
        TextView hh = text(13, 0x99FFFFFF, false); hh.setText("Escaneie o QR code (Android ou iPhone) · Voltar fecha"); hh.setPadding(0, px(8), 0, 0); box.addView(hh);
        qrOverlay.addView(box, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
        root.addView(qrOverlay, new FrameLayout.LayoutParams(-1, -1));
    }

    private void toggleQr() {
        if (qrOverlay.getVisibility() == View.VISIBLE) { qrOverlay.setVisibility(View.GONE); return; }
        Cfg.ensureStarted(this);
        qrAddr.setText(Cfg.url);
        qrImg.setImageBitmap(qrBitmap(Cfg.url, 420));
        qrOverlay.setVisibility(View.VISIBLE);
    }

    private static Bitmap qrBitmap(String text, int size) {
        try {
            BitMatrix m = new QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size);
            Bitmap b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
            for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) b.setPixel(x, y, m.get(x, y) ? Color.BLACK : Color.WHITE);
            return b;
        } catch (Exception e) { return Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888); }
    }
}
