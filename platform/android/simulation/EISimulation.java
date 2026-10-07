// SPDX-License-Identifier: Apache-2.0
package org.cursedlands.simulation;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;
import android.system.ErrnoException;
import android.system.Os;
import android.system.OsConstants;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.godotengine.godot.service.GodotService;

/** A bound, non-exported authority process with the lifetime of its owner. */
public final class EISimulation extends GodotPlugin {
    private final Context context;
    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile Binding active;
    private volatile String error = "";
    private volatile boolean foreground = true;
    private int generation;

    // One connection and reply endpoint per generation. Late Binder callbacks
    // from a stopped process must never stop or initialize its replacement.
    private final class Binding implements ServiceConnection {
        final int id;
        final String[] arguments;
        final Messenger replies;
        Messenger remote;
        IBinder binder;
        volatile boolean stopping;
        boolean bound;
        boolean initialized;
        Binding(int id, String[] arguments) {
            this.id = id;
            this.arguments = arguments;
            replies = new Messenger(new Handler(Looper.getMainLooper(), this::receive));
        }
        @Override public void onServiceConnected(ComponentName name, IBinder service) {
            if (active != this || stopping) { unbind(); return; }
            binder = service;
            try { service.linkToDeath(() -> main.post(this::finished), 0); }
            catch (RemoteException ex) { fail(ex.toString()); return; }
            remote = new Messenger(service);
            Message message = Message.obtain(null, GodotService.MSG_INIT_ENGINE);
            message.getData().putStringArray(GodotService.KEY_COMMAND_LINE_PARAMETERS, arguments);
            send(message);
        }
        @Override public void onServiceDisconnected(ComponentName name) { finished(); }
        @Override public void onBindingDied(ComponentName name) { finished(); }
        @Override public void onNullBinding(ComponentName name) { fail("null service binding"); }
        private boolean receive(Message message) {
            if (active != this || stopping) return true;
            if (message.what == GodotService.MSG_ENGINE_ERROR) {
                fail(message.getData().getString(GodotService.KEY_ENGINE_ERROR, "engine error"));
                return true;
            }
            if (message.what != GodotService.MSG_ENGINE_STATUS_UPDATE) return false;
            String status = message.getData().getString(GodotService.KEY_ENGINE_STATUS, "");
            if (status.equals("INITIALIZED")) {
                // The first step finishes native engine initialization even if
                // the owner went into the background during service startup.
                send(Message.obtain(null, GodotService.MSG_START_ENGINE));
            } else if (status.equals("STARTED")) {
                initialized = true;
                if (!foreground) send(Message.obtain(null, GodotService.MSG_STOP_ENGINE));
            } else if (status.equals("DESTROYED")) {
                stopping = true;
                unbind(); // linkToDeath completes this generation.
            }
            return true;
        }
        void send(Message message) {
            if (remote == null) return;
            message.replyTo = replies;
            try { remote.send(message); }
            catch (RemoteException ex) { fail(ex.toString()); }
        }
        void stop() {
            if (active != this || stopping) return;
            stopping = true;
            if (remote != null) {
                send(Message.obtain(null, GodotService.MSG_DESTROY_ENGINE));
                unbind();
                // Remain busy until the process actually dies. Rebinding a
                // dying Godot singleton cannot safely create a fresh engine.
                if (binder == null || !binder.isBinderAlive()) finished();
            } else {
                // No engine was connected or initialized yet.
                unbind();
                finished();
            }
        }
        void fail(String reason) {
            if (active == this) error = reason;
            stopping = true;
            unbind();
            finished();
        }
        void finished() {
            unbind();
            remote = null;
            if (active == this) active = null;
        }
        void unbind() {
            if (bound) { bound = false; context.unbindService(this); }
        }
    }
    public EISimulation(Godot godot) { super(godot); context = godot.getContext(); }
    @Override public String getPluginName() { return "EISimulation"; }
    @UsedByGodot public synchronized int start(String[] args) {
        if (active != null || args == null || !java.util.Arrays.asList(args).contains("--headless")) return -1;
        Binding binding = new Binding(++generation, args.clone());
        error = "";
        active = binding;
        main.post(() -> {
            if (active != binding || binding.stopping) return;
            try {
                binding.bound = context.bindService(new Intent(context, GodotService.class), binding, Context.BIND_AUTO_CREATE);
                if (!binding.bound) binding.fail("unable to bind simulation service");
            } catch (RuntimeException ex) { binding.fail(ex.toString()); }
        });
        return binding.id;
    }
    @UsedByGodot public boolean is_running(int id) { Binding b = active; return b != null && b.id == id; }
    @UsedByGodot public String last_error() { return error; }
    @UsedByGodot public void stop(int id) {
        Binding b = active;
        if (b != null && b.id == id) main.post(b::stop);
    }
    @UsedByGodot public void set_active(boolean value) {
        foreground = value;
        main.post(() -> {
            Binding b = active;
            if (b != null && b.initialized && !b.stopping)
                b.send(Message.obtain(null, foreground ? GodotService.MSG_START_ENGINE : GodotService.MSG_STOP_ENGINE));
        });
    }
    @UsedByGodot public boolean process_is_alive(int pid) {
        if (pid <= 0) return false;
        try { Os.kill(pid, 0); return true; }
        catch (ErrnoException ex) { return ex.errno == OsConstants.EPERM; }
    }
    @Override public void onMainPause() { set_active(false); }
    @Override public void onMainResume() { set_active(true); }
    @Override public void onMainDestroy() { Binding b = active; if (b != null) main.post(b::stop); }
}
