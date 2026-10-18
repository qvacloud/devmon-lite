package com.qvacloud.devmon.lite;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/** Persistencia simple de la lista de equipos en SharedPreferences (JSON). */
public class Store {
    private static final String KEY = "devices_json";
    private final SharedPreferences sp;

    public Store(Context c) {
        sp = c.getSharedPreferences("devmon_lite", Context.MODE_PRIVATE);
    }

    public List<Device> load() {
        List<Device> out = new ArrayList<>();
        String raw = sp.getString(KEY, "[]");
        try {
            JSONArray arr = new JSONArray(raw);
            for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.optJSONObject(i);
                if (o != null) out.add(Device.fromJson(o));
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    public void save(List<Device> devices) {
        JSONArray arr = new JSONArray();
        for (Device d : devices) arr.put(d.toJson());
        sp.edit().putString(KEY, arr.toString()).apply();
    }
}
