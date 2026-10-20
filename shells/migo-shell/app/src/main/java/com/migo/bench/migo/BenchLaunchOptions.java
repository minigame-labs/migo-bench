package com.migo.bench.migo;

import android.content.Context;
import android.util.Log;

import com.migo.runtime.RuntimeConfig;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * What a game's bundle says it is launched with, handed to the engine: {@code assets/<game>/launch-options.json}, the
 * JSON object a host launches a game with -- the scene, the query of the link that opened it, who referred it.
 * migo-conformance's build.sh puts one in a bundle that checks them; a benchmark game carries none and is launched with
 * the defaults.
 *
 * <p>Through reflection, for {@link BenchNetworkPolicy}'s reason: {@code RuntimeConfig.Builder.setLaunchOptions} is
 * newer than most of the SDKs this shell builds against. An SDK without it has no way to be given launch options, and a
 * bundle that checks them fails, which is what it should report.
 */
final class BenchLaunchOptions {

    private static final String TAG = "BenchLaunchOptions";

    private BenchLaunchOptions() {}

    static void apply(Context context, String asset, RuntimeConfig.Builder builder) {
        String json = BenchAssets.readOptional(context, asset + "/launch-options.json");
        if (json == null) {
            return;
        }
        JSONObject options;
        try {
            options = new JSONObject(json);
        } catch (JSONException e) {
            throw new IllegalStateException(asset + "/launch-options.json is not a JSON object: " + e, e);
        }
        try {
            RuntimeConfig.Builder.class.getMethod("setLaunchOptions", JSONObject.class).invoke(builder, options);
            Log.i(TAG, asset + " is launched with " + options);
        } catch (NoSuchMethodException e) {
            Log.w(TAG, "this SDK cannot be given launch options; " + asset + " is launched with the defaults");
        } catch (ReflectiveOperationException e) {
            Throwable cause = e.getCause() != null ? e.getCause() : e;
            throw new IllegalStateException(asset + "/launch-options.json cannot be applied: " + cause, cause);
        }
    }
}
