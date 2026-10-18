package com.qvacloud.devmon.lite;

import org.json.JSONObject;

import java.util.UUID;

/** Un equipo vigilado. Los campos no persistentes llevan estado en tiempo de ejecucion. */
public class Device {
    public String id;
    public String name;
    public String baseUrl;
    public String token;

    // --- estado en tiempo de ejecucion (no se guarda) ---
    public transient boolean online;
    public transient boolean known;
    public transient long lastSeen;
    public transient long downSince;
    public transient long lastDownMs;
    public transient long lastAlertAt;
    public transient Metrics metrics;

    public Device(String name, String baseUrl, String token) {
        this.id = UUID.randomUUID().toString();
        this.name = name;
        this.baseUrl = stripSlash(baseUrl);
        this.token = token == null ? "" : token;
    }

    static String stripSlash(String u) {
        if (u == null) return "";
        u = u.trim();
        while (u.endsWith("/")) u = u.substring(0, u.length() - 1);
        return u;
    }

    public JSONObject toJson() {
        try {
            JSONObject o = new JSONObject();
            o.put("id", id);
            o.put("name", name);
            o.put("baseUrl", baseUrl);
            o.put("token", token);
            return o;
        } catch (Exception e) {
            return new JSONObject();
        }
    }

    public static Device fromJson(JSONObject o) {
        Device d = new Device(o.optString("name", "Equipo"),
                o.optString("baseUrl", ""), o.optString("token", ""));
        String id = o.optString("id", "");
        if (!id.isEmpty()) d.id = id;
        return d;
    }
}
