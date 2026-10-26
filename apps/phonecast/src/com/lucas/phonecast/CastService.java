package com.lucas.phonecast;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

/** Mantem o processo (e o servidor web) vivo com a TV fora do app. */
public class CastService extends Service {
    @Override public int onStartCommand(Intent i, int flags, int id) {
        Cast.ensureStarted(this);
        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel("cast", "PhoneCast", NotificationManager.IMPORTANCE_MIN);
            ((NotificationManager) getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(ch);
            b = new Notification.Builder(this, "cast");
        } else b = new Notification.Builder(this);
        b.setSmallIcon(android.R.drawable.ic_menu_manage).setContentTitle("PhoneCast ativo").setContentText(Cast.url);
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(1, b.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC); else startForeground(1, b.build());
        } catch (Exception ignored) { }
        return START_STICKY;
    }
    @Override public IBinder onBind(Intent i) { return null; }
}
