package com.lucas.stickhub;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

/** Mantem o processo (e o servidor web) vivo com a TV fora do app. */
public class HubService extends Service {
    @Override public int onStartCommand(Intent i, int flags, int id) {
        Hub.ensureStarted(this);
        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel("hub", "StickHub", NotificationManager.IMPORTANCE_MIN);
            ((NotificationManager) getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(ch);
            b = new Notification.Builder(this, "hub");
        } else b = new Notification.Builder(this);
        b.setSmallIcon(android.R.drawable.ic_menu_manage).setContentTitle("StickHub ativo").setContentText(Hub.url);
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(1, b.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC); else startForeground(1, b.build());
        } catch (Exception ignored) { }
        return START_STICKY;
    }
    @Override public IBinder onBind(Intent i) { return null; }
}
