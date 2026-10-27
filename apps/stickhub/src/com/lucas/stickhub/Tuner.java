package com.lucas.stickhub;

import com.lucas.common.Adb;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/** Perfis de otimizacao (os mesmos de firetv/*.sh) rodados pelo ADB local da TV. */
final class Tuner {
    private static final String[] DEBLOAT = {
        "com.amazon.shoptv.client", "com.amazon.shoptv.firetv.client", "com.amazon.minitv.android.app",
        "com.amazon.imdb.tv.android.app", "com.imdb.livingroom.firetv", "com.amazon.naatyam",
        "com.amazon.bueller.music", "com.amazon.bueller.photos", "com.amazon.bueller.notification",
        "com.amazon.gamehub", "com.amazon.recess", "com.amazon.tv.livetv", "com.amazon.tv.releasenotes",
        "com.amazon.perfcollection", "com.amazon.logan", "com.amazon.dp.logger", "com.amazon.device.logmanager",
        "com.amazon.tv.fw.metrics", "com.amazon.wirelessmetrics.service", "com.amazon.device.crashmanager",
        "com.amazon.connectivitydiag"};
    private static final String[] PRIVACY_KEYS = {
        "limit_ad_tracking", "non_amz_limit_ad_tracking", "amz_limit_ad_tracking",
        "advertisingIdApp:interestBasedAds:value", "USAGE_METRICS_UPLOAD_ENABLED", "usage_metrics_marketing_enabled",
        "settingsApp:appUsageData:value", "settingsApp:deviceUsageData:value", "screensaver_enabled"};
    private static final int[] PRIVACY_ON = {1, 1, 1, 0, 0, 0, 0, 0, 0};
    private static final int[] PRIVACY_OFF = {0, 0, 0, 1, 1, 1, 1, 1, 1};

    static volatile String status = "";
    private static volatile boolean running;

    private Tuner() {}

    static boolean known(String name) {
        return Arrays.asList("animacoes", "animacoes-off", "debloat", "debloat-off", "privacidade", "privacidade-off", "compilar").contains(name);
    }

    static List<String> commands(String name) {
        List<String> c = new ArrayList<>();
        if (name.equals("animacoes") || name.equals("animacoes-off")) {
            String v = name.equals("animacoes") ? "0.5" : "1";
            for (String k : new String[] {"window_animation_scale", "transition_animation_scale", "animator_duration_scale"})
                c.add("settings put global " + k + " " + v);
        } else if (name.equals("debloat")) {
            for (String p : DEBLOAT) c.add("pm disable-user --user 0 " + p);
        } else if (name.equals("debloat-off")) {
            for (String p : DEBLOAT) c.add("pm enable " + p);
        } else if (name.equals("privacidade") || name.equals("privacidade-off")) {
            int[] v = name.equals("privacidade") ? PRIVACY_ON : PRIVACY_OFF;
            for (int i = 0; i < PRIVACY_KEYS.length; i++) c.add("settings put secure " + PRIVACY_KEYS[i] + " " + v[i]);
        } else if (name.equals("compilar")) {
            c.add("pm trim-caches 999G");
            c.add("cmd package compile -m speed -f com.amazon.tv.launcher");
            c.add("cmd package compile -m speed -f com.amazon.tv.settings.v2");
        }
        return c;
    }

    /** Roda o perfil em segundo plano; acompanhe por {@link #status}. */
    static synchronized boolean start(final String name) {
        if (running || !known(name)) return false;
        running = true;
        status = "rodando:" + name;
        new Thread(new Runnable() {
            public void run() {
                try {
                    List<String> cmds = commands(name);
                    for (int i = 0; i < cmds.size(); i++) {
                        status = "rodando:" + name + ":" + (i + 1) + "/" + cmds.size();
                        Adb.shell(cmds.get(i), 600000);
                    }
                    status = "ok:" + name;
                } catch (Exception e) {
                    status = "erro:" + name + ":" + e.getMessage();
                } finally {
                    running = false;
                }
            }
        }, "tuner").start();
        return true;
    }
}
