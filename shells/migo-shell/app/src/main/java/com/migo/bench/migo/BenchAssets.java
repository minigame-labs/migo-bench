package com.migo.bench.migo;

import android.content.Context;

import java.io.ByteArrayOutputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/** The files a game's bundle carries beside its code, which say how the host runs it. */
final class BenchAssets {

    private BenchAssets() {}

    /** The asset's text, or null when the bundle has no such file. */
    static String readOptional(Context context, String path) {
        try (InputStream in = context.getAssets().open(path)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        } catch (FileNotFoundException e) {
            return null;
        } catch (IOException e) {
            throw new IllegalStateException("cannot read " + path, e);
        }
    }
}
