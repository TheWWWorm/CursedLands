// SPDX-License-Identifier: Apache-2.0
package org.cursedlands.simulation;

import android.app.Application;

/** Runs before any Activity, engine initialization or graphics driver call. */
public final class StartupApplication extends Application {
    @Override public void onCreate() {
        super.onCreate();
        EarlyStartup.begin(this);
    }
}
