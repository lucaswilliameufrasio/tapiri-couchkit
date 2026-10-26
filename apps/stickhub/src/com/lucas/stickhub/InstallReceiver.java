package com.lucas.stickhub;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;

/** Recebe o resultado da instalacao; repassa o pedido de confirmacao para a tela da TV. */
public class InstallReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c, Intent i) {
        int st = i.getIntExtra(PackageInstaller.EXTRA_STATUS, -1);
        if (st == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            Intent confirm = i.getParcelableExtra(Intent.EXTRA_INTENT);
            if (confirm != null) c.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } else if (st == PackageInstaller.STATUS_SUCCESS) Hub.installStatus = "instalado";
        else Hub.installStatus = "falhou: " + i.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
    }
}
