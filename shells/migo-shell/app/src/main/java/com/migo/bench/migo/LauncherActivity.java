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
        deployGame();
        RuntimeConfig cfg = new RuntimeConfig.Builder(this)
                .setDebugEnabled(true)
                .setCodeSigningEnabled(false)
                .build();
        BenchGameActivity.launch(this, GAME_ID, ENTRY, cfg);
        finish();
    }

    // Copy assets/game/{game.js,game.json} -> filesDir/migo/games/bench/code/.
    private void deployGame() {
        File code = new File(getFilesDir(), "migo/games/" + GAME_ID + "/code");
        if (!code.exists() && !code.mkdirs()) {
            Log.e(TAG, "could not create code dir " + code);
            return;
        }
        copyAsset("game/game.js", new File(code, "game.js"));
        copyAsset("game/game.json", new File(code, "game.json"));
        Log.i(TAG, "deployed game -> " + code.getAbsolutePath());
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
