package com.qvacloud.devmon.lite;

import android.content.Context;
import android.content.SharedPreferences;

/** Preferencias de la app: pantalla, alertas y umbrales. */
public class Settings {
    private static final String P = "devmon_prefs";
    private final SharedPreferences sp;

    public Settings(Context c) {
        sp = c.getSharedPreferences(P, Context.MODE_PRIVATE);
    }

    public boolean keepScreenOn() { return sp.getBoolean("keepScreenOn", false); }
    public void setKeepScreenOn(boolean v) { sp.edit().putBoolean("keepScreenOn", v).apply(); }

    public boolean alertsEnabled() { return sp.getBoolean("alerts", true); }
    public void setAlertsEnabled(boolean v) { sp.edit().putBoolean("alerts", v).apply(); }

    public double cpuThreshold() { return sp.getFloat("cpu", 90f); }
    public double memThreshold() { return sp.getFloat("mem", 90f); }
    public double tempThreshold() { return sp.getFloat("temp", 80f); }
    public double diskThreshold() { return sp.getFloat("disk", 90f); }

    public void setThresholds(double cpu, double mem, double temp, double disk) {
        sp.edit()
                .putFloat("cpu", (float) cpu)
                .putFloat("mem", (float) mem)
                .putFloat("temp", (float) temp)
                .putFloat("disk", (float) disk)
                .apply();
    }

    public int alertCooldownMin() { return sp.getInt("cooldown", 10); }
    public void setAlertCooldownMin(int v) { sp.edit().putInt("cooldown", v).apply(); }
}
