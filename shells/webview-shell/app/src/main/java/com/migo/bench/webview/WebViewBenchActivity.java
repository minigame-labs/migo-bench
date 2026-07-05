package com.migo.bench.webview;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.os.Bundle;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebSettings;

/**
 * Minimal fullscreen WebView host -- the modern WebView baseline for Migo
 * benchmarks.
 *
 * Loads a self-contained HTML5 game from {@code file:///android_asset/game/}
 * (placed there by {@code bench/scripts/pack-game.sh}). The settings below are
 * the WebView's best-case configuration on purpose: a fair baseline must let
 * WebView run as fast as it can, otherwise Migo's win is meaningless to a
 * buyer. We do NOT cripple the WebView to make Migo look better.
 */
public class WebViewBenchActivity extends Activity {

    private WebView webView;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Keep the screen on during the (up to) 5-minute benchmark run.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        webView = new WebView(this);
        setContentView(webView);

        // Immersive fullscreen so the rendered area matches Migo's surface and
        // gfxinfo frame counts compare like-for-like.
        webView.setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        // Allow the game's local storage / canvas-heavy workloads to behave as
        // they would in a real embedded game center.
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        // Let file:// assets reference each other (sub-resources, workers).
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        // Render at full device width; games handle their own scaling.
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setCacheMode(WebSettings.LOAD_NO_CACHE);

        // High render priority (deprecated no-op on modern WebView, but
        // harmless and documents intent / helps on older System WebView).
        //noinspection deprecation
        settings.setRenderPriority(WebSettings.RenderPriority.HIGH);

        // Keep navigation inside the WebView; never spawn a browser.
        webView.setWebViewClient(new WebViewClient());

        // Bridge so the game signals its first real frame -> reportFullyDrawn(),
        // giving WebView the same system "game-ready" cold-start metric as Migo's
        // onGameReady (the fair startup number; "Displayed" fires on the blank window).
        webView.addJavascriptInterface(new BenchBridge(), "AndroidBench");

        // Layer type HARDWARE: ensure the WebView composites on the GPU so
        // dumpsys gfxinfo sees real frame timing (matches Migo's GPU path).
        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);

        // Which game asset dir to load (default "game"; "game-stress" for the ramp curve).
        String asset = getIntent().getStringExtra("game_asset");
        if (asset == null || asset.trim().isEmpty()) {
            asset = "game";
        }
        webView.loadUrl("file:///android_asset/" + asset + "/index.html");
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (webView != null) {
            webView.onPause();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) {
            webView.onResume();
        }
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }

    /** JS-callable bridge: the game calls AndroidBench.ready() on its first frame. */
    private final class BenchBridge {
        private boolean reported = false;

        @JavascriptInterface
        public void ready() {
            runOnUiThread(() -> {
                if (!reported) {
                    reported = true;
                    reportFullyDrawn();
                }
            });
        }
    }
}
