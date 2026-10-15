// SPDX-License-Identifier: Apache-2.0
package org.cursedlands.simulation;

import android.app.Application;
import android.app.ActivityManager;
import android.content.Context;
import android.os.Build;
import android.os.Process;
import android.util.AtomicFile;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Durable handoff from Android process creation to the game's crash marker.
 * Only an unfinished launch changes the next renderer. Completed sessions are
 * owned by CrashReport/RendererChoice, including their background/quit rules.
 */
final class EarlyStartup {
    private static final String TAG = "CursedLandsStartup";
    private static final int MAX_FAILURES = 4;
    private static final int MAX_JOURNAL = 2 * 1024 * 1024;
    private static EarlyStartup instance;
    private final Context context;
    private final File files;
    private final AtomicFile journal;
    private JSONObject state;
    private JSONObject current;

    private EarlyStartup(Context context) {
        this.context = context.getApplicationContext();
        files = context.getFilesDir(); // GodotIO.getDataDir(): user:// on Android.
        journal = new AtomicFile(new File(files, "crash/android-startup.json"));
    }

    static synchronized void begin(Context context) {
        if (context == null || instance != null) return;
        try {
            if (!mainProcess(context)) return;
            EarlyStartup next = new EarlyStartup(context);
            next.start();
            instance = next;
        } catch (IOException | JSONException | RuntimeException ex) {
            Log.e(TAG, "Could not persist early startup diagnostics", ex);
        }
    }

    private static boolean mainProcess(Context context) {
        if (Build.VERSION.SDK_INT >= 28) return context.getPackageName().equals(Application.getProcessName());
        ActivityManager manager = context.getSystemService(ActivityManager.class);
        java.util.List<ActivityManager.RunningAppProcessInfo> processes = manager == null ? null : manager.getRunningAppProcesses();
        if (processes == null) return false;
        for (ActivityManager.RunningAppProcessInfo process : processes) {
            if (process.pid == Process.myPid()) return context.getPackageName().equals(process.processName);
        }
        return false;
    }

    private void start() throws IOException, JSONException {
        state = new JSONObject();
        if (journal.getBaseFile().exists() || new File(journal.getBaseFile() + ".bak").exists()) {
            try (FileInputStream stream = journal.openRead()) {
                state = new JSONObject(read(stream, MAX_JOURNAL));
            } catch (IOException | JSONException ex) {
                // A corrupt diagnostic file must not prevent the game opening.
                Log.e(TAG, "Unreadable early startup journal", ex);
            }
        }
        JSONArray failures = state.optJSONArray("failures");
        if (failures == null) failures = new JSONArray();
        JSONObject old = state.optJSONObject("active");
        String recovered = "";
        // Android may start the process only to serve a FileProvider request.
        // The plugin arms tracking before native initialization; a process
        // that never attempted the engine must not reset a working renderer.
        if (valid(old) && !old.optString("startup_stage").equals("android_application_start")) {
            old.put("last", "android startup interrupted: " + old.optString("startup_stage"));
            attachExit(old);
            captureLog(old);
            // Archive first: a death while applying fallback must not lose it.
            JSONArray kept = new JSONArray();
            for (int i = Math.max(0, failures.length() - MAX_FAILURES + 1); i < failures.length(); i++) {
                JSONObject entry = failures.getJSONObject(i);
                if (!entry.optString("session").equals(old.optString("session"))) kept.put(entry);
            }
            kept.put(old);
            failures = kept;
            state.put("failures", failures);
            save();
            String requested = old.optString("requested_renderer");
            if (requested.equals("mobile") || requested.equals("forward_plus")) {
                write(new AtomicFile(new File(files, "renderer.cfg")),
                        "[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\nrenderer/rendering_method.mobile=\"gl_compatibility\"\n");
                recovered = requested;
            }
        }
        String session = UUID.randomUUID().toString().replace("-", "").substring(0, 12);
        long now = System.currentTimeMillis();
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        String stamp = format.format(new Date(now));
        current = new JSONObject();
        current.put("session", session).put("pid", Process.myPid()).put("started_ms", now)
                .put("started", stamp).put("updated", stamp).put("zone", "(menu)")
                .put("state", "foreground").put("focus", "in")
                .put("startup_stage", "android_application_start")
                .put("last", "android startup: before engine initialization")
                .put("requested_renderer", renderer()).put("recovered_renderer", recovered)
                .put("os", "Android API " + Build.VERSION.SDK_INT)
                .put("device", Build.MANUFACTURER + " " + Build.MODEL)
                .put("android_exit_registered", AndroidExitReport.register(context, session));
        File log = new File(files, "logs/godot.log");
        current.put("log_before_modified", log.lastModified()).put("log_before_size", log.length());
        try { current.put("version", context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName); }
        catch (android.content.pm.PackageManager.NameNotFoundException ignored) {}
        state.put("active", current).put("failures", failures);
        save();
        Log.i(TAG, "session " + session + ": before engine, requested=" + current.optString("requested_renderer") + ", recovered=" + recovered);
    }

    private static boolean valid(JSONObject record) {
        return record != null && record.optString("session").matches("[0-9a-f]{12}") && record.optInt("pid") > 0;
    }

    private String renderer() throws IOException {
        File config = new File(files, "renderer.cfg");
        if (!config.exists()) return "gl_compatibility";
        String section = "", selected = "gl_compatibility", mobile = "";
        try (FileInputStream stream = new FileInputStream(config)) {
            for (String line : read(stream, 16384).split("\n")) {
                line = line.trim();
                if (line.startsWith("[")) { section = line; continue; }
                if (!section.equals("[rendering]")) continue;
                String[] parts = line.split("=", 2);
                if (parts.length != 2) continue;
                String value = parts[1].trim().replace("\"", "");
                if (parts[0].trim().equals("renderer/rendering_method")) selected = value;
                if (parts[0].trim().equals("renderer/rendering_method.mobile")) mobile = value;
            }
        }
        return mobile.isEmpty() ? selected : mobile;
    }

    private void captureLog(JSONObject record) throws JSONException {
        File log = new File(files, "logs/godot.log");
        if (!log.isFile() || (log.lastModified() == record.optLong("log_before_modified") && log.length() == record.optLong("log_before_size"))) return;
        try (RandomAccessFile stream = new RandomAccessFile(log, "r")) {
            int size = (int) Math.min(stream.length(), 65536);
            byte[] bytes = new byte[size];
            stream.seek(stream.length() - size);
            stream.readFully(bytes);
            record.put("startup_log", new String(bytes, StandardCharsets.UTF_8));
            record.put("startup_log_truncated", stream.length() > size);
        } catch (IOException ex) { record.put("startup_log_error", ex.getClass().getSimpleName()); }
    }

    private void attachExit(JSONObject record) throws JSONException {
        JSONObject previous = record.optJSONObject("android_exit");
        if (previous != null && previous.optString("native_trace_status").equals("available")) return;
        if (!record.optBoolean("android_exit_registered")) return;
        JSONObject exit = new JSONObject(AndroidExitReport.read(context, record.optInt("pid"), record.optString("session")));
        if (exit.length() != 0) record.put("android_exit", exit);
    }

    static synchronized void stage(String stage) {
        if (instance == null || instance.current == null) return;
        try {
            instance.current.put("startup_stage", stage);
            instance.save();
            Log.i(TAG, stage);
        } catch (IOException | JSONException ex) { Log.e(TAG, "Could not save startup stage", ex); }
    }

    static synchronized String diagnostics() {
        if (instance == null) return "{}";
        try {
            JSONArray failures = instance.state.getJSONArray("failures");
            for (int i = 0; i < failures.length(); i++) instance.attachExit(failures.getJSONObject(i));
            instance.save(); // Keep the OS trace even if another launch fails.
            return new JSONObject().put("current", instance.current == null ? JSONObject.NULL : instance.current)
                    .put("failures", failures).toString();
        } catch (IOException | JSONException ex) {
            Log.e(TAG, "Could not refresh startup diagnostics", ex);
            return "{}";
        }
    }

    /** Called only after the regular, matching crash marker is saved. */
    static synchronized boolean complete(String session) {
        if (instance == null || instance.current == null || !instance.current.optString("session").equals(session)) return false;
        try {
            instance.state.remove("active");
            instance.save();
            instance.current = null;
            Log.i(TAG, "handed off to game crash tracking: " + session);
            return true;
        } catch (IOException ex) { Log.e(TAG, "Could not finish startup tracking", ex); return false; }
    }

    /** Successful report export acknowledges only the failures it contains. */
    static synchronized void acknowledge(String session) {
        if (instance == null) return;
        try {
            JSONArray failures = instance.state.getJSONArray("failures"), kept = new JSONArray();
            for (int i = 0; i < failures.length(); i++) {
                JSONObject entry = failures.getJSONObject(i);
                if (!entry.optString("session").equals(session)) kept.put(entry);
            }
            instance.state.put("failures", kept);
            instance.save();
        } catch (IOException | JSONException ex) { Log.e(TAG, "Could not acknowledge startup report", ex); }
    }

    private void save() throws IOException { write(journal, state.toString()); }

    private static void write(AtomicFile file, String text) throws IOException {
        FileOutputStream stream = null;
        try {
            stream = file.startWrite();
            stream.write(text.getBytes(StandardCharsets.UTF_8));
            file.finishWrite(stream);
        } catch (IOException ex) { if (stream != null) file.failWrite(stream); throw ex; }
    }

    private static String read(FileInputStream stream, int limit) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[4096];
        int count;
        while ((count = stream.read(buffer)) != -1) {
            if (out.size() + count > limit) throw new IOException("diagnostic file limit");
            out.write(buffer, 0, count);
        }
        return out.toString("UTF-8");
    }
}
