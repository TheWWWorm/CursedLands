// SPDX-License-Identifier: Apache-2.0
package org.cursedlands.simulation;

import android.app.ActivityManager;
import android.app.Application;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.os.Build;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import org.json.JSONException;
import org.json.JSONObject;

/** Read the OS's post-mortem record; never intercept native signals in Godot. */
final class AndroidExitReport {
    private AndroidExitReport() {}

    private static byte[] token(String session) {
        if (session == null || !session.matches("[0-9a-f]{12}")) return null;
        return ("cursedlands:" + session).getBytes(StandardCharsets.US_ASCII);
    }

    static boolean register(Context context, String session) {
        byte[] state = token(session);
        if (Build.VERSION.SDK_INT < 30 || state == null) return false;
        try {
            // The separately hosted simulation has its own lifetime and reports.
            if (!context.getPackageName().equals(Application.getProcessName())) return false;
            ActivityManager manager = context.getSystemService(ActivityManager.class);
            if (manager == null) return false;
            manager.setProcessStateSummary(state);
            return true;
        } catch (RuntimeException ex) {
            return false; // Diagnostics must not prevent startup on an OEM build.
        }
    }

    static String read(Context context, int pid, String session) {
        byte[] state = token(session);
        if (Build.VERSION.SDK_INT < 30 || pid <= 0 || state == null) return "{}";
        try {
            ActivityManager manager = context.getSystemService(ActivityManager.class);
            if (manager == null) return "{}";
            String name = context.getPackageName();
            for (ApplicationExitInfo exit : manager.getHistoricalProcessExitReasons(name, pid, 8)) {
                // A PID can be reused. Never attach an unrelated session or service crash.
                if (exit.getPid() != pid || !name.equals(exit.getProcessName()) ||
                        !Arrays.equals(state, exit.getProcessStateSummary())) continue;
                JSONObject report = new JSONObject();
                report.put("session", session);
                report.put("pid", pid);
                report.put("process", exit.getProcessName());
                report.put("timestamp_ms", exit.getTimestamp());
                report.put("reason", exit.getReason());
                report.put("status", exit.getStatus());
                report.put("importance", exit.getImportance());
                // These are the OS's last samples, not peak or total device RAM.
                report.put("last_pss_kb", exit.getPss());
                report.put("last_rss_kb", exit.getRss());
                String description = exit.getDescription();
                if (description != null) report.put("description", description.substring(0, Math.min(description.length(), 2048)));
                if (Build.VERSION.SDK_INT >= 31 && exit.getReason() == ApplicationExitInfo.REASON_CRASH_NATIVE) {
                    report.put("native_trace_status", "unavailable");
                    try (InputStream stream = exit.getTraceInputStream()) {
                        if (stream != null) {
                            report.put("native_trace", NativeTombstone.read(stream, pid));
                            report.put("native_trace_status", "available");
                        }
                    } catch (IOException | RuntimeException ex) {
                        // History survives even when a tombstone expired, is oversized,
                        // or uses an unsupported/corrupt format. Keep the exit reason.
                        report.put("native_trace_status", "unreadable");
                        report.put("native_trace_error", ex.getClass().getSimpleName());
                    }
                }
                return report.toString();
            }
        } catch (RuntimeException | JSONException ex) {
            // Optional API: older templates / OS versions retain ordinary game logs.
        }
        return "{}";
    }
}
