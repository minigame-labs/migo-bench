package com.migo.bench.migo;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Build;

import com.migo.runtime.callback.PermissionHandler;
import com.migo.runtime.callback.PermissionSink;

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * The shell's permission policy. It runs only content its own developers put in it -- the benchmark games and the
 * conformance suite -- so a scope that content asks for is granted, as a host that trusts what it runs would. A scope
 * that needs an Android runtime permission (location, the microphone, the camera, Bluetooth from Android 12 on) is
 * granted only once Android has granted that permission to the app, asked for here when it has not, and refused when
 * Android refuses it: the SDK reads the app's own permission when the game uses the capability, so a scope granted
 * without it would fail anyway.
 * <p>
 * The player changes those permissions on the app's page in Android's settings, which is where the shell's openSetting
 * sends them (BenchSettingHandler): {@link #reread} reads the permissions again when they come back and records what a
 * change there decided.
 */
final class BenchPermissionHandler implements PermissionHandler {

    /** The Android runtime permissions behind a scope; scopes not listed need none. */
    private static final Map<String, String[]> ANDROID_PERMISSIONS = new HashMap<>();

    static {
        ANDROID_PERMISSIONS.put("scope.userLocation", new String[] {
                Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION});
        ANDROID_PERMISSIONS.put("scope.record", new String[] {Manifest.permission.RECORD_AUDIO});
        ANDROID_PERMISSIONS.put("scope.camera", new String[] {Manifest.permission.CAMERA});
        // Android 12's "nearby devices", asked for together: connecting, scanning and advertising. Before it,
        // Bluetooth's permissions are granted with the app.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ANDROID_PERMISSIONS.put("scope.bluetooth", new String[] {
                    Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_ADVERTISE});
        }
    }

    /** A scope request waiting for Android's answer to the permission dialog. */
    private static final class Pending {
        final int requestId;
        final String scope;
        final PermissionSink sink;

        Pending(int requestId, String scope, PermissionSink sink) {
            this.requestId = requestId;
            this.scope = scope;
            this.sink = sink;
        }
    }

    private final Activity activity;
    private final Map<Integer, Pending> pending = new HashMap<>();
    private int nextRequestCode = 0x4d00;
    /** Every scope decided in this session, as it now stands, in the order content first asked about it. */
    private final Map<String, Boolean> decided = new LinkedHashMap<>();
    /** The session's sink, as the SDK hands it with each request: the standing decisions are the session's. */
    private PermissionSink standing;

    BenchPermissionHandler(Activity activity) {
        this.activity = activity;
    }

    @Override
    public void requestScope(int requestId, String scope, String desc, PermissionSink sink) {
        String[] needed = ANDROID_PERMISSIONS.get(scope);
        if (needed == null || anyGranted(needed)) {
            decide(scope, sink, requestId, true);
            return;
        }
        activity.runOnUiThread(() -> {
            if (activity.isFinishing() || activity.isDestroyed()) {
                sink.failRequest(requestId, "no activity to ask in");
                return;
            }
            int requestCode;
            synchronized (pending) {
                requestCode = nextRequestCode++;
                pending.put(requestCode, new Pending(requestId, scope, sink));
            }
            activity.requestPermissions(needed, requestCode);
        });
    }

    /** Android's answer to a dialog this handler opened; anything else is not this handler's. */
    boolean onRequestPermissionsResult(int requestCode, int[] grantResults) {
        Pending request;
        synchronized (pending) {
            request = pending.remove(requestCode);
        }
        if (request == null) return false;
        boolean granted = false;
        for (int result : grantResults) {
            granted |= result == PackageManager.PERMISSION_GRANTED;
        }
        decide(request.scope, request.sink, request.requestId, granted);
        return true;
    }

    /** Record the standing decision first, then settle the request, as the sink's contract asks. */
    private void decide(String scope, PermissionSink sink, int requestId, boolean granted) {
        synchronized (decided) {
            decided.put(scope, granted);
            standing = sink;
        }
        sink.setScope(scope, granted);
        sink.resolveRequest(requestId, granted);
    }

    /**
     * The decided scopes once the player is back from Android's settings: a scope behind a permission stands as
     * Android now holds it -- one revoked there is refused from now on -- and the rest as they were decided.
     */
    Map<String, Boolean> reread() {
        Map<String, Boolean> changed = new LinkedHashMap<>();
        Map<String, Boolean> now;
        PermissionSink sink;
        synchronized (decided) {
            for (Map.Entry<String, Boolean> scope : decided.entrySet()) {
                String[] needed = ANDROID_PERMISSIONS.get(scope.getKey());
                if (needed == null) continue;
                boolean granted = anyGranted(needed);
                if (granted != scope.getValue()) changed.put(scope.getKey(), granted);
            }
            decided.putAll(changed);
            now = new LinkedHashMap<>(decided);
            sink = standing;
        }
        if (sink != null) {
            for (Map.Entry<String, Boolean> scope : changed.entrySet()) sink.setScope(scope.getKey(), scope.getValue());
        }
        return now;
    }

    /** Any one of a scope's alternatives is enough: coarse location is location. */
    private boolean anyGranted(String[] permissions) {
        for (String permission : permissions) {
            if (activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return true;
        }
        return false;
    }
}
