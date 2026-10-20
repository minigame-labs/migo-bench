package com.migo.bench.migo;

import android.content.Context;
import android.util.Log;

import com.migo.runtime.RuntimeConfig;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.lang.reflect.Method;
import java.util.Iterator;
import java.util.Locale;

/**
 * The network a game's bundle says it needs, handed to the engine: {@code assets/<game>/network-policy.json}, in the
 * JSON a host gives the engine -- a domain list or {@code "unrestricted"} per channel ({@code request},
 * {@code download}, {@code upload}, {@code socket}, {@code tcp}, {@code udp}), {@code allowPlainHttp}, {@code lan}.
 * migo-conformance's build.sh puts one in a bundle whose checks reach the network; a benchmark game carries none and
 * gets none, which is what a product grants by default.
 *
 * <p>Through reflection, because this shell builds against every published SDK (the harness reproduces any release's
 * numbers with that release's AAR) and {@code NetworkPolicy} is newer than most of them. An SDK without it grants
 * content every network, so there is nothing to hand it. A policy that cannot be applied stops the launch: a run
 * under a network other than the one its bundle names would report on the wrong thing.
 */
final class BenchNetworkPolicy {

    private static final String TAG = "BenchNetworkPolicy";

    private BenchNetworkPolicy() {}

    static void apply(Context context, String asset, RuntimeConfig.Builder builder) {
        String json = BenchAssets.readOptional(context, asset + "/network-policy.json");
        if (json == null) {
            return;
        }
        Class<?> policyClass;
        try {
            policyClass = Class.forName("com.migo.runtime.NetworkPolicy");
        } catch (ClassNotFoundException e) {
            Log.i(TAG, "this SDK has no NetworkPolicy and grants every network; " + asset + "'s is not needed");
            return;
        }
        try {
            Class<?> channelClass = Class.forName("com.migo.runtime.NetworkPolicy$Channel");
            Class<?> builderClass = Class.forName("com.migo.runtime.NetworkPolicy$Builder");
            Object policyBuilder = builderClass.getConstructor().newInstance();
            Method allow = builderClass.getMethod("allow", channelClass, String[].class);
            Method allowUnrestricted = builderClass.getMethod("allowUnrestricted", channelClass);
            JSONObject spec = new JSONObject(json);
            for (Iterator<String> keys = spec.keys(); keys.hasNext(); ) {
                String key = keys.next();
                if (key.equals("allowPlainHttp")) {
                    builderClass.getMethod("setAllowPlainHttp", boolean.class)
                            .invoke(policyBuilder, spec.getBoolean(key));
                } else if (key.equals("lan")) {
                    builderClass.getMethod("setAllowLocalNetwork", boolean.class)
                            .invoke(policyBuilder, spec.getBoolean(key));
                } else {
                    Object channel = channelNamed(channelClass, key);
                    if ("unrestricted".equals(spec.get(key))) {
                        allowUnrestricted.invoke(policyBuilder, channel);
                    } else {
                        JSONArray list = spec.getJSONArray(key);
                        String[] domains = new String[list.length()];
                        for (int i = 0; i < domains.length; i++) {
                            domains[i] = list.getString(i);
                        }
                        allow.invoke(policyBuilder, channel, (Object) domains);
                    }
                }
            }
            Object policy = builderClass.getMethod("build").invoke(policyBuilder);
            RuntimeConfig.Builder.class.getMethod("setNetworkPolicy", policyClass).invoke(builder, policy);
            Log.i(TAG, asset + "'s network: " + policy);
        } catch (ReflectiveOperationException | JSONException e) {
            Throwable cause = e.getCause() != null ? e.getCause() : e;
            throw new IllegalStateException(asset + "/network-policy.json cannot be applied: " + cause, cause);
        }
    }

    private static Object channelNamed(Class<?> channelClass, String key) throws JSONException {
        for (Object channel : channelClass.getEnumConstants()) {
            if (((Enum<?>) channel).name().toLowerCase(Locale.ROOT).equals(key)) {
                return channel;
            }
        }
        throw new JSONException("no channel named \"" + key + "\"");
    }
}
