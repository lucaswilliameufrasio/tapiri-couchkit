package com.lucas.stickhub;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.media.AudioManager;
import android.os.Build;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

/**
 * Teclas do controle remoto sem ADB. O Couchkit liga este servico uma vez (pelo
 * ADB, na configuracao) e depois a depuracao pode ser desligada: Voltar/Home
 * sao acoes globais, as setas movem o foco e OK clica no item em foco.
 * Volume e midia usam o AudioManager e nao precisam do servico.
 */
public class KeyService extends AccessibilityService {
    private static volatile KeyService inst;

    @Override protected void onServiceConnected() { inst = this; }
    @Override public boolean onUnbind(android.content.Intent i) { inst = null; return super.onUnbind(i); }
    @Override public void onAccessibilityEvent(AccessibilityEvent e) { }
    @Override public void onInterrupt() { }

    static boolean active() { return inst != null; }

    /** Executa a tecla; false se nao ha como (servico desligado ou tecla sem equivalente). */
    static boolean press(Context c, int code) {
        AudioManager am = (AudioManager) c.getSystemService(Context.AUDIO_SERVICE);
        switch (code) {
            case KeyEvent.KEYCODE_VOLUME_UP: am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI); return true;
            case KeyEvent.KEYCODE_VOLUME_DOWN: am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI); return true;
            case KeyEvent.KEYCODE_VOLUME_MUTE:
                try {
                    if (Build.VERSION.SDK_INT >= 23) am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_TOGGLE_MUTE, AudioManager.FLAG_SHOW_UI);
                    else am.setStreamMute(AudioManager.STREAM_MUSIC, !am.isStreamMute(AudioManager.STREAM_MUSIC));
                    return true;
                } catch (SecurityException e) { return false; }
            case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE: case KeyEvent.KEYCODE_MEDIA_REWIND: case KeyEvent.KEYCODE_MEDIA_FAST_FORWARD:
                am.dispatchMediaKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, code));
                am.dispatchMediaKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, code));
                return true;
            default: break;
        }
        KeyService s = inst;
        if (s == null) return false;
        switch (code) {
            case KeyEvent.KEYCODE_BACK: return s.performGlobalAction(GLOBAL_ACTION_BACK);
            case KeyEvent.KEYCODE_HOME: return s.performGlobalAction(GLOBAL_ACTION_HOME);
            case KeyEvent.KEYCODE_DPAD_UP: return s.move(33);
            case KeyEvent.KEYCODE_DPAD_DOWN: return s.move(130);
            case KeyEvent.KEYCODE_DPAD_LEFT: return s.move(17);
            case KeyEvent.KEYCODE_DPAD_RIGHT: return s.move(66);
            case KeyEvent.KEYCODE_DPAD_CENTER: case KeyEvent.KEYCODE_ENTER: return s.click();
            case 223: return s.performGlobalAction(GLOBAL_ACTION_POWER_DIALOG);
            default: return false;
        }
    }

    private AccessibilityNodeInfo focused() {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) return null;
        AccessibilityNodeInfo f = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (f == null) f = root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY);
        return f;
    }

    /** direction: View.FOCUS_UP=33, DOWN=130, LEFT=17, RIGHT=66. */
    private boolean move(int direction) {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) return false;
        AccessibilityNodeInfo from = focused();
        if (from == null) from = root;
        AccessibilityNodeInfo next = from.focusSearch(direction);
        if (next == null) return false;
        return next.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
    }

    private boolean click() {
        AccessibilityNodeInfo n = focused();
        while (n != null) {
            if (n.isClickable() && n.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true;
            n = n.getParent();
        }
        return false;
    }

    /** Acrescenta texto ao campo em foco. */
    static boolean type(String add) {
        KeyService s = inst;
        if (s == null) return false;
        AccessibilityNodeInfo n = s.focused();
        if (n == null || !n.isEditable()) return false;
        CharSequence old = n.getText();
        Bundle b = new Bundle();
        b.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, (old == null ? "" : old.toString()) + add);
        return n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, b);
    }

    /** Apaga o ultimo caractere do campo em foco. */
    static boolean backspace() {
        KeyService s = inst;
        if (s == null) return false;
        AccessibilityNodeInfo n = s.focused();
        if (n == null || !n.isEditable()) return false;
        CharSequence old = n.getText();
        if (old == null || old.length() == 0) return true;
        Bundle b = new Bundle();
        b.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, old.subSequence(0, old.length() - 1));
        return n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, b);
    }
}
