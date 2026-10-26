package com.lucas.phonecast;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.*;

/** Toca na TV o que o celular enviou: video, audio ou foto. OK pausa, setas buscam, Voltar fecha. */
public class PlayerActivity extends Activity {
    static volatile PlayerActivity cur;
    volatile String title = "", kind = "";
    private VideoView video; private ImageView image; private TextView label, big; private LinearLayout bar;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Runnable hide = new Runnable() { public void run() { bar.setVisibility(View.GONE); } };
    private float dp;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        dp = getResources().getDisplayMetrics().density;
        FrameLayout root = new FrameLayout(this); root.setBackgroundColor(Color.BLACK);
        video = new VideoView(this); root.addView(video, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
        image = new ImageView(this); image.setScaleType(ImageView.ScaleType.FIT_CENTER); root.addView(image, new FrameLayout.LayoutParams(-1, -1));
        big = new TextView(this); big.setTextColor(0x55FFFFFF); big.setTextSize(80); big.setGravity(Gravity.CENTER); big.setText("♪");
        root.addView(big, new FrameLayout.LayoutParams(-1, -1));
        bar = new LinearLayout(this); bar.setOrientation(LinearLayout.VERTICAL); bar.setPadding(px(40), px(16), px(40), px(16));
        GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, new int[]{0xCC000000, 0x00000000}); bar.setBackground(g);
        label = new TextView(this); label.setTextColor(Color.WHITE); label.setTextSize(20); label.setSingleLine(true);
        bar.addView(label);
        root.addView(bar, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
        setContentView(root);
        load(getIntent());
    }

    @Override protected void onNewIntent(Intent i) { super.onNewIntent(i); setIntent(i); load(i); }
    @Override protected void onResume() { super.onResume(); cur = this; }
    @Override protected void onDestroy() { if (cur == this) cur = null; try { video.stopPlayback(); } catch (Exception ignored) { } super.onDestroy(); }

    private int px(float v) { return (int) (v * dp + 0.5f); }

    private void load(Intent i) {
        String src = i.getStringExtra("src"); kind = i.getStringExtra("kind"); title = i.getStringExtra("title");
        if (src == null) { finish(); return; }
        label.setText(title); flash();
        video.stopPlayback(); video.setVisibility(View.GONE); image.setVisibility(View.GONE); big.setVisibility(View.GONE);
        if ("image".equals(kind)) {
            image.setVisibility(View.VISIBLE); image.setImageBitmap(decode(src));
        } else {
            video.setVisibility("audio".equals(kind) ? View.INVISIBLE : View.VISIBLE); if ("audio".equals(kind)) big.setVisibility(View.VISIBLE);
            video.setOnErrorListener(new android.media.MediaPlayer.OnErrorListener() { public boolean onError(android.media.MediaPlayer m, int w, int e) {
                Toast.makeText(PlayerActivity.this, "Formato não suportado pela TV", Toast.LENGTH_LONG).show(); return true; } });
            video.setOnCompletionListener(new android.media.MediaPlayer.OnCompletionListener() { public void onCompletion(android.media.MediaPlayer m) { flash(); } });
            if (src.startsWith("http")) video.setVideoURI(Uri.parse(src)); else video.setVideoPath(src);
            video.start();
        }
    }

    private Bitmap decode(String path) {
        BitmapFactory.Options o = new BitmapFactory.Options(); o.inJustDecodeBounds = true; BitmapFactory.decodeFile(path, o);
        int s = 1; while (o.outWidth / (s * 2) >= 1920 || o.outHeight / (s * 2) >= 1080) s *= 2;
        o.inJustDecodeBounds = false; o.inSampleSize = s; return BitmapFactory.decodeFile(path, o);
    }

    private void flash() { bar.setVisibility(View.VISIBLE); ui.removeCallbacks(hide); ui.postDelayed(hide, 3500); }

    boolean isPlaying() { try { return !"image".equals(kind) && video.isPlaying(); } catch (Exception e) { return false; } }
    int pos() { try { return "image".equals(kind) ? 0 : video.getCurrentPosition(); } catch (Exception e) { return 0; } }
    int dur() { try { return "image".equals(kind) ? 0 : Math.max(0, video.getDuration()); } catch (Exception e) { return 0; } }

    void control(String cmd, int v) {
        if (cmd.equals("stop")) { finish(); return; }
        if ("image".equals(kind)) return;
        if (cmd.equals("toggle")) { if (video.isPlaying()) video.pause(); else video.start(); }
        else if (cmd.equals("seek")) video.seekTo(Math.max(0, Math.min(video.getDuration(), video.getCurrentPosition() + v * 1000)));
        else if (cmd.equals("to")) video.seekTo(v * 1000);
        flash();
    }

    @Override public boolean onKeyDown(int k, KeyEvent e) {
        switch (k) {
            case KeyEvent.KEYCODE_DPAD_CENTER: case KeyEvent.KEYCODE_ENTER: case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE: control("toggle", 0); return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT: case KeyEvent.KEYCODE_MEDIA_FAST_FORWARD: control("seek", 10); return true;
            case KeyEvent.KEYCODE_DPAD_LEFT: case KeyEvent.KEYCODE_MEDIA_REWIND: control("seek", -10); return true;
        }
        return super.onKeyDown(k, e);
    }
}
