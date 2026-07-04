package com.migo.bench.migo;

import android.content.Context;
import android.content.Intent;
import android.util.Log;

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

    public static void launch(Context ctx, String gameId, String entry, RuntimeConfig cfg) {
        Intent it = buildLaunchIntent(ctx, BenchGameActivity.class, gameId, entry, cfg);
        ctx.startActivity(it);
    }

    @Override
    protected void onSessionCreated(GameSession session) {
        // Single-package game, no remote subpackages, no auth (bunnymark needs none).
        session.setSubpackageHandler(new BenchSubpackageHandler(session.getPaths().getCodeDir()));
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
                Log.i(TAG, "onGameReady");
                reportFullyDrawn();   // system cold-start signal
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
}
