package com.migo.bench.migo;

import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import com.migo.runtime.GameSession;
import com.migo.runtime.MigoException;
import com.migo.runtime.MigoGameActivity;
import com.migo.runtime.RuntimeConfig;
import com.migo.runtime.callback.GameSessionListener;

/**
 * Minimal Migo host for benchmarking: loads one game, no menu, no auth relay.
 * Calls reportFullyDrawn() at first game frame so ActivityManager emits a
 * system-level "Fully drawn +Xms" cold-start signal (the harness reads that).
 */
public class BenchGameActivity extends MigoGameActivity {

    private static final String TAG = "BenchGameActivity";

    private static final String GAME_ID = "bench";
    private static final String ENTRY = "game.js";

    /**
     * An intent that reaches this activity with no config attached.
     *
     * Deliberately not {@code buildLaunchIntent}: that carries the config
     * through an in-process table, which the harness cannot use because it
     * starts this activity with `am start`. The config comes from
     * {@link #onCreateRuntimeConfig()} instead, so both routes -- icon tap and
     * `am start` -- run the game exactly the same way.
     */
    public static Intent intentFor(Context ctx, String gameAsset) {
        Intent it = new Intent(ctx, BenchGameActivity.class);
        it.putExtra(EXTRA_GAME_ID, GAME_ID);
        it.putExtra(EXTRA_ENTRY_POINT, ENTRY);
        if (gameAsset != null && !gameAsset.trim().isEmpty()) {
            it.putExtra("game_asset", gameAsset);
        }
        return it;
    }

    @Override
    protected RuntimeConfig onCreateRuntimeConfig() {
        String asset = getIntent().getStringExtra("game_asset");
        if (asset == null || asset.trim().isEmpty()) {
            asset = "game";
        }
        deployGame(asset);
        RuntimeConfig.Builder builder = new RuntimeConfig.Builder(this)
                // Off, as a product would ship it. It only registers an
                // in-process console ring buffer, which is small -- but it is a
                // cost the WebView side has no equivalent of, and a benchmark
                // should not measure a runtime in a configuration nobody
                // releases. Game console output still reaches logcat, which is
                // where both this harness and the conformance suite read it
                // from; that was checked, not assumed.
                .setDebugEnabled(false)
                // Off deliberately, and it makes the two sides more alike rather
                // than less: WebView verifies nothing per file beyond the APK
                // signature, so per-file integrity checking on one side only
                // would be measuring a feature the other does not have.
                .setCodeSigningEnabled(false)
                // Give the games the same `AndroidBench.ready()` they call on the
                // WebView side, so both runtimes report game-ready from the same
                // line of the same game.
                //
                // They did not before. The WebView shell exposes `AndroidBench` as
                // a JavascriptInterface and the game calls it from its first frame;
                // this shell reported `Fully drawn` from the engine's own
                // `onGameReady`, which fires when module evaluation finishes --
                // *before* the first frame, by the engine's own estimate 16-50 ms
                // before. The comparison therefore measured an earlier event on one
                // side than the other, in Migo's favour, and the published
                // game-ready margins were overstated by that much.
                .addPreludeScript("bench-ready-bridge", BENCH_READY_BRIDGE);
        // Honour the game's declared orientation (game.json `deviceOrientation`)
        // so landscape games rotate before the surface is created and the runtime
        // boots against the correctly-sized surface.
        String orientation = readGameOrientation(asset);
        if (orientation != null) {
            builder.setStartupOrientation(orientation);
            Log.i(TAG, "startup orientation from game.json: " + orientation);
        }
        return builder.build();
    }

    @Override
    protected void onSessionCreated(GameSession session) {
        // Single-package game, no remote subpackages, no auth (bunnymark needs none).
        session.setSubpackageHandler(new BenchSubpackageHandler(session.getPaths().getCodeDir()));
        // Game-ready comes from the game, not from the engine. See the comment on
        // onGameReady below for why that distinction is the whole point.
        session.setGameLogHandler(logJson -> {
            if (logJson != null && logJson.contains(READY_KEY)) {
                reportGameReadyOnce();
            }
        });
    }

    /** The key `LauncherActivity`'s injected `AndroidBench.ready()` reports under. */
    private static final String READY_KEY = "bench.game-ready";

    private final java.util.concurrent.atomic.AtomicBoolean reported =
            new java.util.concurrent.atomic.AtomicBoolean(false);

    /**
     * `reportFullyDrawn()` exactly once, from whichever thread the log arrives on.
     *
     * The games call `AndroidBench.ready()` from their first rendered frame and
     * only their first; the guard is here because the log channel is not the
     * game's to promise and a repeat would move the measurement.
     */
    private void reportGameReadyOnce() {
        if (!reported.compareAndSet(false, true)) {
            return;
        }
        runOnUiThread(() -> {
            Log.i(TAG, "game-ready from the game's first frame");
            reportFullyDrawn();
        });
    }

    @Override
    protected void onLaunchFailed(int errorCode, String message) {
        Log.e(TAG, "Launch failed: [" + errorCode + "] " + message);
        super.onLaunchFailed(errorCode, message);
    }

    @Override
    protected GameSessionListener onCreateGameListener() {
        return new GameSessionListener() {
            @Override
            public void onGameReady() {
                // Deliberately NOT the cold-start signal any more.
                //
                // This fires when the engine finishes evaluating the game's
                // module -- before the first frame, by the engine's own estimate
                // 16-50 ms before. The WebView shell reports `Fully drawn` from
                // the game's first-frame callback. Reporting from here made the
                // two runtimes' "game-ready" different events, measured earlier
                // on Migo's side, and every published margin was overstated by
                // that gap. The signal now comes from the game, identically on
                // both sides; see `onSessionCreated`.
                Log.i(TAG, "onGameReady (engine-side; not the cold-start signal)");
            }

            @Override public void onGameExit(int exitCode) { Log.i(TAG, "onGameExit " + exitCode); }

            @Override public void onError(MigoException exception) { Log.e(TAG, "onError: " + exception); }

            @Override public void onLoadingStart() {}
            @Override public void onLoadingEnd() {}
            @Override public void onLoadingProgress(float progress, String message) {}
            @Override public void onPaused() {}
            @Override public void onResumed() {}
            @Override public void onDestroyed() {}
        };
    }

    /**
     * The `AndroidBench` the games expect, routed through the one channel Migo
     * gives a host for game-originated events.
     *
     * `gameLog` rather than `console`: console output goes to logcat, and this
     * shell needs the callback, not the log. `BenchGameActivity` listens for the
     * key below and calls `reportFullyDrawn()` once.
     */
    private static final String BENCH_READY_BRIDGE =
            "globalThis.AndroidBench = {"
            + "  ready: function () {"
            + "    try {"
            + "      getGameLogManager({}).log({"
            + "        level: 'info', key: 'bench.game-ready', value: 1"
            + "      });"
            + "    } catch (e) {}"
            + "  }"
            + "};";

    private String readGameOrientation(String asset) {
        try (InputStream in = getAssets().open(asset + "/game.json")) {
            java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
            String json = bos.toString("UTF-8").trim();
            if (json.isEmpty()) return null;
            String o = new org.json.JSONObject(json).optString("deviceOrientation", "");
            if ("landscape".equals(o) || "portrait".equals(o)) return o;
        } catch (Exception e) {
            Log.w(TAG, "could not read game.json orientation for " + asset + ": " + e);
        }
        return null;
    }

    // Copy assets/<asset>/{game.js,game.json} -> filesDir/migo/games/bench/code/.
    private void deployGame(String asset) {
        File code = new File(getFilesDir(), "migo/games/" + GAME_ID + "/code");
        if (!code.exists() && !code.mkdirs()) {
            Log.e(TAG, "could not create code dir " + code);
            return;
        }
        // Once per game version, not once per launch.
        //
        // Re-extracting the bundle on every cold start put an asset copy --
        // 1.2 MB for the Phaser game -- inside the measured window, which the
        // webview shell never pays: it loads from `file:///android_asset/`
        // directly. Neither does a real Migo host, which extracts when it
        // installs or downloads a game and then launches it many times. The
        // stamp keys on the asset name and the APK's install time, so switching
        // games or reinstalling the shell still re-deploys.
        File stamp = new File(code, ".deployed-from");
        String want = asset + "@" + apkInstallTime();
        if (want.equals(readText(stamp))) {
            Log.i(TAG, "game '" + asset + "' already deployed");
            return;
        }
        // The whole bundle, not just its two required files. This used to copy
        // game.js and game.json by name, so any bundle carrying an asset -- a
        // font, an image, a sub-package -- arrived on the device without it,
        // and the game failed at runtime with no sign of why. Text conformance
        // has to ship its own typeface, which is how that surfaced.
        copyAssetTree(asset, code);
        writeText(stamp, want);
        Log.i(TAG, "deployed game '" + asset + "' -> " + code.getAbsolutePath());
    }

    private long apkInstallTime() {
        try {
            return getPackageManager()
                    .getPackageInfo(getPackageName(), 0)
                    .lastUpdateTime;
        } catch (Exception e) {
            // Unknown install time means "re-deploy": a stamp that cannot be
            // trusted must not be the reason a stale bundle survives.
            return System.currentTimeMillis();
        }
    }

    private static String readText(File f) {
        try (InputStream in = new java.io.FileInputStream(f)) {
            java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[256];
            int n;
            while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
            return bos.toString("UTF-8").trim();
        } catch (Exception e) {
            return null;
        }
    }

    private static void writeText(File f, String text) {
        try (OutputStream out = new FileOutputStream(f)) {
            out.write(text.getBytes("UTF-8"));
        } catch (IOException e) {
            // A stamp that could not be written just means the next launch
            // re-deploys; it must never fail the launch.
        }
    }

    /** Copy an assets/ subtree onto disk, creating directories as it goes. */
    private void copyAssetTree(String assetDir, File destDir) {
        String[] names;
        try {
            names = getAssets().list(assetDir);
        } catch (Exception e) {
            Log.e(TAG, "could not list assets in " + assetDir + ": " + e);
            return;
        }
        if (names == null) {
            return;
        }
        for (String name : names) {
            String child = assetDir + "/" + name;
            String[] grandchildren;
            try {
                grandchildren = getAssets().list(child);
            } catch (Exception e) {
                grandchildren = null;
            }
            // AssetManager has no isDirectory: a directory lists children, a
            // file lists none. An empty directory is indistinguishable from a
            // file here and there is no reason for a bundle to contain one.
            if (grandchildren != null && grandchildren.length > 0) {
                File sub = new File(destDir, name);
                if (!sub.exists() && !sub.mkdirs()) {
                    Log.e(TAG, "could not create " + sub);
                    continue;
                }
                copyAssetTree(child, sub);
            } else {
                copyAsset(child, new File(destDir, name));
            }
        }
    }

    private void copyAsset(String assetPath, File dest) {
        try (InputStream in = getAssets().open(assetPath);
             OutputStream out = new FileOutputStream(dest)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
        } catch (IOException e) {
            Log.e(TAG, "deploy failed: " + assetPath, e);
        }
    }
}
