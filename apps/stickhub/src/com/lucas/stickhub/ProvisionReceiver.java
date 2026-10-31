package com.lucas.stickhub;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import com.lucas.common.Pair;

/**
 * Recebe o token escolhido pelo Couchkit durante a configuracao por ADB.
 * A permissao DUMP so o shell do ADB tem: apps comuns da TV nao conseguem
 * trocar o token. Os apps irmaos leem o novo token pelo PairProvider.
 */
public class ProvisionReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c, Intent i) {
        String t = i.getStringExtra("token");
        if (t == null || !t.matches("[A-Za-z0-9]{6,64}")) return;
        Hub.ensureStarted(c);
        SharedPreferences p = c.getApplicationContext().getSharedPreferences("hub", Context.MODE_PRIVATE);
        Pair.set(p, t);
        Hub.token = t;
        Hub.url = "http://" + Hub.localIp() + ":" + Hub.port + "/?k=" + t;
    }
}
