package com.qvacloud.devmon.lite;

import org.json.JSONArray;
import org.json.JSONObject;

/** Instantanea de metricas ya parseada, lista para pintar. */
public class Metrics {
    public String os = "";
    public String arch = "";
    public double cpu;
    public int cores;
    public double memPercent;
    public long memUsed;
    public long memTotal;
    public Double temp;           // null si no hay sensores
    public String diskLabel = "";
    public double diskPercent;
    public double uptimeSec;

    public static Metrics parse(JSONObject o) {
        Metrics m = new Metrics();
        m.os = o.optString("os", "");
        m.arch = o.optString("arch", "");
        m.uptimeSec = o.optDouble("uptime_s", 0);
        JSONObject cpu = o.optJSONObject("cpu");
        if (cpu != null) {
            m.cpu = cpu.optDouble("usage_percent", 0);
            m.cores = cpu.optInt("cores", 0);
        }
        JSONObject mem = o.optJSONObject("mem");
        if (mem != null) {
            m.memUsed = mem.optLong("used", 0);
            m.memTotal = mem.optLong("total", 0);
            m.memPercent = mem.optDouble("used_percent", 0);
        }
        JSONArray temps = o.optJSONArray("temps");
        if (temps != null && temps.length() > 0) {
            double t = -273;
            for (int i = 0; i < temps.length(); i++) {
                JSONObject e = temps.optJSONObject(i);
                if (e != null) t = Math.max(t, e.optDouble("celsius", -273));
            }
            if (t > -273) m.temp = t;
        }
        JSONArray disks = o.optJSONArray("disks");
        if (disks != null && disks.length() > 0) {
            JSONObject d = disks.optJSONObject(0);
            if (d != null) {
                m.diskLabel = d.optString("mount", "");
                m.diskPercent = d.optDouble("used_percent", 0);
            }
        }
        return m;
    }
}
