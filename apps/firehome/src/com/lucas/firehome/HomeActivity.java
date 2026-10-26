package com.lucas.firehome;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;

import java.text.SimpleDateFormat;
import java.util.*;

public class HomeActivity extends Activity {
    private static final String[] DEFAULT_PINS = {
        "com.netflix.ninja", "com.amazon.firetv.youtube", "com.hbo.hbonow", "tv.pluto.android", "tv.twitch.android.viewer",
        "com.apple.atve.amazon.appletv", "com.limelight", "com.lucas.phonebro"};
    private static final String[] HIDE_LABELS = {"Game Center", "Kids", "Live Shopping", "miniTV", "Amazon Music", "Amazon Photos", "Shop", "IMDb", "Naatyam", "Notícias", "Appstore"};
    private static final String SETTINGS_PKG = "com.amazon.tv.settings.v2";

    private final Handler ui = new Handler(Looper.getMainLooper());
    private SharedPreferences prefs;
    private PackageManager pm;
    private float dp;
    private LinearLayout content;
    private TextView clock, date, mem;
    private final Runnable tick = new Runnable() { public void run() { updateClock(); ui.postDelayed(this, 15000); } };

    private static class Item {
        String label, glyph; Drawable img; boolean banner; Intent intent; Runnable action; String pkg;
    }

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = getSharedPreferences("firehome", MODE_PRIVATE); pm = getPackageManager(); dp = getResources().getDisplayMetrics().density;
        GradientDrawable bg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{0xFF0B1020, 0xFF1B1140, 0xFF3A1550});
        FrameLayout root = new FrameLayout(this); root.setBackground(bg);

        LinearLayout page = new LinearLayout(this); page.setOrientation(LinearLayout.VERTICAL);
        LinearLayout top = new LinearLayout(this); top.setGravity(Gravity.CENTER_VERTICAL); top.setPadding(px(56), px(32), px(56), 0);
        clock = text(52, Color.WHITE, true); date = text(18, 0xAAFFFFFF, false); date.setPadding(px(18), px(18), 0, 0);
        mem = text(16, 0x88FFFFFF, false); mem.setGravity(Gravity.RIGHT);
        top.addView(clock); top.addView(date); top.addView(mem, new LinearLayout.LayoutParams(0, -2, 1));
        page.addView(top);

        ScrollView sv = new ScrollView(this); sv.setFillViewport(false); sv.setClipChildren(false); sv.setVerticalScrollBarEnabled(false);
        content = new LinearLayout(this); content.setOrientation(LinearLayout.VERTICAL); content.setPadding(0, px(8), 0, px(16)); content.setClipChildren(false); content.setClipToPadding(false);
        sv.addView(content); page.addView(sv, new LinearLayout.LayoutParams(-1, 0, 1));
        root.addView(page, new FrameLayout.LayoutParams(-1, -1));
        TextView hint = text(14, 0x99FFFFFF, false); hint.setText("OK abrir   ·   segure OK para fixar ou remover dos favoritos"); hint.setGravity(Gravity.CENTER);
        hint.setPadding(0, px(8), 0, px(14)); hint.setBackgroundColor(0x55000000);
        page.addView(hint, new LinearLayout.LayoutParams(-1, -2));
        setContentView(root);
    }

    @Override protected void onResume() { super.onResume(); build(); ui.post(tick); }
    @Override protected void onPause() { super.onPause(); ui.removeCallbacks(tick); }
    @Override protected void onNewIntent(Intent i) { super.onNewIntent(i); if (content != null && content.getChildCount() > 0) content.requestFocus(); }
    @Override public void onBackPressed() { /* launcher: nao sai */ }

    private int px(float v) { return (int) (v * dp + 0.5f); }

    private TextView text(int sp, int color, boolean bold) {
        TextView t = new TextView(this); t.setTextSize(sp); t.setTextColor(color); t.setSingleLine(true);
        if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT_BOLD); return t;
    }

    private void updateClock() {
        Date now = new Date();
        clock.setText(new SimpleDateFormat("HH:mm", Locale.getDefault()).format(now));
        date.setText(new SimpleDateFormat("EEEE, d 'de' MMMM", new Locale("pt", "BR")).format(now));
        ActivityManager am = (ActivityManager) getSystemService(ACTIVITY_SERVICE); ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
        am.getMemoryInfo(mi); mem.setText("RAM livre " + (mi.availMem >> 20) + " MB");
    }

    // ---------- Dados ----------
    private List<Item> installedApps() {
        Map<String, Item> map = new LinkedHashMap<String, Item>();
        for (int pass = 0; pass < 2; pass++) {
            Intent q = new Intent(Intent.ACTION_MAIN).addCategory(pass == 0 ? Intent.CATEGORY_LEANBACK_LAUNCHER : Intent.CATEGORY_LAUNCHER);
            for (ResolveInfo ri : pm.queryIntentActivities(q, 0)) {
                String pkg = ri.activityInfo.packageName;
                if (pkg.equals(getPackageName()) || pkg.equals(SETTINGS_PKG) || map.containsKey(pkg)) continue;
                if (pass == 1 && (ri.activityInfo.applicationInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0) continue;
                String lbl = String.valueOf(ri.loadLabel(pm)); if (hidden(lbl)) continue;
                Item it = new Item(); it.pkg = pkg; it.label = lbl;
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

    private static boolean hidden(String l) { for (String h : HIDE_LABELS) if (l.contains(h)) return true; return false; }

    private Set<String> pins() {
        String s = prefs.getString("pins", null);
        return new LinkedHashSet<String>(Arrays.asList((s == null ? join(DEFAULT_PINS) : s).split(",")));
    }

    private static String join(String[] a) { StringBuilder b = new StringBuilder(); for (String s : a) b.append(b.length() > 0 ? "," : "").append(s); return b.toString(); }

    private void togglePin(String pkg) {
        Set<String> p = pins(); if (!p.remove(pkg)) p.add(pkg);
        StringBuilder b = new StringBuilder(); for (String s : p) b.append(b.length() > 0 ? "," : "").append(s);
        prefs.edit().putString("pins", b.toString()).apply();
        build();
        Toast.makeText(this, "Favoritos atualizados", Toast.LENGTH_SHORT).show();
    }

    private Item tool(String label, String glyph, Runnable r, Intent i) {
        Item it = new Item(); it.label = label; it.action = r; it.intent = i;
        GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{0xFF3A4A9A, 0xFF7A3AA0}); it.img = g; it.glyph = glyph; return it;
    }

    // ---------- UI ----------
    private void build() {
        content.removeAllViews();
        List<Item> all = installedApps(); Set<String> pinned = pins();
        List<Item> fav = new ArrayList<Item>(), rest = new ArrayList<Item>();
        Map<String, Item> byPkg = new HashMap<String, Item>(); for (Item i : all) byPkg.put(i.pkg, i);
        for (String p : pinned) if (byPkg.containsKey(p)) fav.add(byPkg.get(p));
        for (Item i : all) if (!pinned.contains(i.pkg)) rest.add(i);
        Collections.sort(rest, new Comparator<Item>() { public int compare(Item a, Item b) { return a.label.compareToIgnoreCase(b.label); } });

        List<Item> sys = new ArrayList<Item>();
        sys.add(tool("Configurações", "gear", null, settingsIntent()));
        sys.add(tool("Limpar RAM", "bolt", new Runnable() { public void run() { cleanRam(); } }, null));
        sys.add(tool("Rede", "wifi", null, new Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)));
        content.addView(spacer());
        addRow("Favoritos", fav, true);
        addRow("Todos os apps", rest, false);
        addRow("Sistema", sys, false);
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
        final int ring = px(8), w = px(big ? 232 : 180), h = px(big ? 130 : 101);
        LinearLayout c = new LinearLayout(this); c.setOrientation(LinearLayout.VERTICAL); c.setGravity(Gravity.CENTER_HORIZONTAL);
        LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(w + 2 * ring, -2); clp.setMargins(px(6), 0, px(6), 0); c.setLayoutParams(clp);
        c.setFocusable(true); c.setClickable(true);
        c.setContentDescription(it.label);

        // anel de foco: fica FORA do container recortado, entao nunca e cortado
        final GradientDrawable focusRing = new GradientDrawable(); focusRing.setCornerRadius(px(18)); focusRing.setColor(Color.TRANSPARENT);
        FrameLayout ringBox = new FrameLayout(this); ringBox.setPadding(ring, ring, ring, ring); ringBox.setBackground(new android.graphics.drawable.InsetDrawable(focusRing, px(2)));

        FrameLayout box = new FrameLayout(this);
        GradientDrawable shape = new GradientDrawable(); shape.setCornerRadius(px(14)); shape.setColor(0x22FFFFFF); box.setBackground(shape);
        box.setClipToOutline(true);
        box.setOutlineProvider(new android.view.ViewOutlineProvider() { public void getOutline(View v, android.graphics.Outline o) { o.setRoundRect(0, 0, v.getWidth(), v.getHeight(), px(14)); } });
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

        TextView l = text(14, Color.WHITE, false); l.setSingleLine(false); l.setMaxLines(2); l.setMinLines(2); l.setText(it.label);
        l.setGravity(Gravity.CENTER_HORIZONTAL | Gravity.TOP); l.setPadding(px(4), px(6), px(4), 0); l.setAlpha(0.78f);
        l.setEllipsize(android.text.TextUtils.TruncateAt.END); c.addView(l, new LinearLayout.LayoutParams(w + 2 * ring, -2));

        c.setOnFocusChangeListener(new View.OnFocusChangeListener() {
            public void onFocusChange(View v, boolean has) {
                
                v.setElevation(has ? px(12) : 0);
                focusRing.setStroke(px(3), has ? 0xFF5CC8FF : Color.TRANSPARENT);
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
}
