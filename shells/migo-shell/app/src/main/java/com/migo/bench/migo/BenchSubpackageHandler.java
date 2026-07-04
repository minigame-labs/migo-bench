package com.migo.bench.migo;

import android.util.Log;

import com.migo.runtime.callback.SubpackageHandler;

import java.io.File;

/**
 * Minimal SubpackageHandler: succeeds only when a subpackage directory already
 * exists under codeDir (no remote download). bunnymark has no subpackages, so
 * this is effectively a no-op — present for correctness with the runtime API.
 */
public final class BenchSubpackageHandler implements SubpackageHandler {

    private static final String TAG = "BenchSubpackage";
    private final File codeDir;

    public BenchSubpackageHandler(File codeDir) {
        if (codeDir == null) {
            throw new IllegalArgumentException("codeDir cannot be null");
        }
        this.codeDir = codeDir;
    }

    @Override
    public void download(SubpackageRequest request, DownloadCallback callback) {
        if (callback == null) {
            return;
        }
        if (request == null || request.root == null || request.root.trim().isEmpty()) {
            callback.onFailure("invalid subpackage request");
            return;
        }
        String root = request.root.trim();
        if (root.contains("..")) {
            callback.onFailure("invalid subpackage root: " + root);
            return;
        }
        File targetDir = new File(codeDir, root);
        if (targetDir.isDirectory()) {
            callback.onProgress(100, 1, 1);
            callback.onSuccess(null);
            Log.i(TAG, "Using existing subpackage: " + targetDir.getAbsolutePath());
            return;
        }
        callback.onFailure("subpackage not found: " + targetDir.getAbsolutePath());
    }
}
