package com.migo.bench.migo;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;

import com.migo.runtime.callback.SettingHandler;
import com.migo.runtime.callback.SettingSink;

/**
 * The shell's settings, as openSetting opens them. The shell's scopes stand behind Android's permissions
 * (BenchPermissionHandler), so the page a player changes them on is the app's own page in Android's settings: this
 * opens it over the game, and when the player comes back answers with the scopes content has asked about as they now
 * stand -- recording first what a change made there decided.
 */
final class BenchSettingHandler implements SettingHandler {
    private static final int REQUEST_CODE = 0x4e00;

    private final Activity activity;
    private final BenchPermissionHandler permissions;
    /** The call waiting for the player to come back; one at a time, as there is one settings page to be on. */
    private SettingSink waiting;

    BenchSettingHandler(Activity activity, BenchPermissionHandler permissions) {
        this.activity = activity;
        this.permissions = permissions;
    }

    @Override
    public void openSetting(SettingSink sink) {
        activity.runOnUiThread(() -> {
            if (activity.isFinishing() || activity.isDestroyed()) {
                sink.fail(-1, "openSetting:fail no activity to open the settings over");
                return;
            }
            synchronized (this) {
                if (waiting != null) {
                    sink.fail(-1, "openSetting:fail the settings are already open");
                    return;
                }
                waiting = sink;
            }
            Intent page = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", activity.getPackageName(), null));
            try {
                activity.startActivityForResult(page, REQUEST_CODE);
            } catch (ActivityNotFoundException e) {
                synchronized (this) {
                    waiting = null;
                }
                sink.fail(-1, "openSetting:fail this device has no settings page for the app");
            }
        });
    }

    /** The player back from the page this handler opened; anything else is not this handler's. */
    boolean onActivityResult(int requestCode) {
        if (requestCode != REQUEST_CODE) return false;
        SettingSink sink;
        synchronized (this) {
            sink = waiting;
            waiting = null;
        }
        if (sink != null) sink.settleOpened(permissions.reread());
        return true;
    }
}
