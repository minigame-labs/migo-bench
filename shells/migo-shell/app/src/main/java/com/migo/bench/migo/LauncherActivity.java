package com.migo.bench.migo;

import android.app.Activity;
import android.os.Bundle;

/**
 * The icon entry point, and nothing else.
 *
 * It used to deploy the game and build the RuntimeConfig before starting
 * BenchGameActivity, which put an activity transition and a full asset copy
 * inside the measured window -- neither of which the webview shell pays, since
 * it is one activity loading straight from `file:///android_asset/`. A
 * benchmark that measures one shell's structure against another's is not
 * measuring the runtimes.
 *
 * Both now live in {@link BenchGameActivity#onCreateRuntimeConfig()}, so the
 * harness starts that activity directly -- one activity per side -- and tapping
 * the icon still reaches the same place through here.
 */
public class LauncherActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        startActivity(BenchGameActivity.intentFor(this, getIntent().getStringExtra("game_asset")));
        finish();
    }
}
