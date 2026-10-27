package com.lucas.common;

import android.content.ContentResolver;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import java.util.UUID;

/**
 * Token compartilhado entre os apps da TV. O StickHub e o dono: os outros
 * apps pedem o token dele por um provider protegido por permissao de assinatura
 * (so apps assinados com a mesma chave leem). Sem o StickHub instalado, cada app
 * usa o proprio token aleatorio. O token continua sendo exigido em toda chamada.
 */
public final class Pair {
    public static final String HUB_PACKAGE = "com.lucas.stickhub";
    private static final Uri URI = Uri.parse("content://" + HUB_PACKAGE + ".pair/token");
    private static final long REFRESH_MS = 10_000;

    private static Context ctx;
    private static SharedPreferences prefs;
    private static volatile String token = "";
    private static volatile long checked;

    private Pair() {}

    /** Chame uma vez ao iniciar o app; devolve o token em uso. */
    public static synchronized String init(Context context, SharedPreferences p) {
        ctx = context.getApplicationContext();
        prefs = p;
        String own = p.getString("token", null);
        if (own == null) {
            own = UUID.randomUUID().toString().substring(0, 8);
            p.edit().putString("token", own).apply();
        }
        token = own;
        refresh();
        return token;
    }

    /** Token atual; reconsulta o StickHub de tempos em tempos. */
    public static String token() {
        if (System.currentTimeMillis() - checked > REFRESH_MS) refresh();
        return token;
    }

    private static synchronized void refresh() {
        checked = System.currentTimeMillis();
        if (ctx == null || ctx.getPackageName().equals(HUB_PACKAGE)) return;
        ContentResolver cr = ctx.getContentResolver();
        Cursor c = null;
        try {
            c = cr.query(URI, null, null, null, null);
            if (c != null && c.moveToFirst()) {
                String shared = c.getString(0);
                if (shared != null && shared.length() >= 6 && !shared.equals(token)) {
                    token = shared;
                    prefs.edit().putString("token", shared).apply();
                }
            }
        } catch (RuntimeException ignore) {
            // StickHub ausente ou sem permissao: segue com o token proprio
        } finally {
            if (c != null) c.close();
        }
    }
}
