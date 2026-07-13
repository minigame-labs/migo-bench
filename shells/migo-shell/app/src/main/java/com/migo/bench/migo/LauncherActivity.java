package com.migo.bench.migo;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;

import com.migo.runtime.RuntimeConfig;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Auto-forwarding launcher: deploys the bundled game into the runtime's private
 * code dir, then launches BenchGameActivity and finishes. No menu, no user tap
 * (mirror of webview-shell launching straight to the game).
 */
public class LauncherActivity extends Activity {

    private static final String TAG = "BenchLauncher";
    private static final String GAME_ID = "bench";
    private static final String ENTRY = "game.js";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Which bundled game asset dir to deploy (default "game"; "game-stress" for the ramp curve).
        String asset = getIntent().getStringExtra("game_asset");
        if (asset == null || asset.trim().isEmpty()) {
            asset = "game";
        }
        deployGame(asset);
        // Honor the game's declared orientation (game.json `deviceOrientation`)
        // so landscape games (e.g. the Phaser endless-runner) rotate the
        // activity to landscape before the surface is created. The runtime
        // then boots against the correctly-sized surface.
        RuntimeConfig.Builder builder = new RuntimeConfig.Builder(this)
                .setDebugEnabled(true)
                .setCodeSigningEnabled(false);
        String orientation = readGameOrientation(asset);
        if (orientation != null) {
            builder.setStartupOrientation(orientation);
            Log.i(TAG, "startup orientation from game.json: " + orientation);
        }
        BenchGameActivity.launch(this, GAME_ID, ENTRY, builder.build());
        finish();
    }

    // Read `deviceOrientation` ("landscape"/"portrait") from the game's game.json.
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
        copyAsset(asset + "/game.js", new File(code, "game.js"));
        copyAsset(asset + "/game.json", new File(code, "game.json"));
        Log.i(TAG, "deployed game '" + asset + "' -> " + code.getAbsolutePath());
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
