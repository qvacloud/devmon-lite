package com.qvacloud.devmon.lite;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/** Cliente HTTP minimo contra el agente (sin dependencias externas). */
public class Net {
    public static final int TIMEOUT_MS = 2500;

    /** Devuelve el cuerpo de /metrics o null si falla/expira/da 401. */
    public static String fetchMetrics(Device d) {
        HttpURLConnection c = null;
        try {
            URL url = new URL(d.baseUrl + "/metrics");
            c = (HttpURLConnection) url.openConnection();
            c.setConnectTimeout(TIMEOUT_MS);
            c.setReadTimeout(TIMEOUT_MS);
            c.setRequestMethod("GET");
            c.setUseCaches(false);
            if (d.token != null && !d.token.isEmpty()) {
                c.setRequestProperty("X-Auth-Token", d.token);
            }
            int code = c.getResponseCode();
            if (code != 200) return null;
            InputStream in = c.getInputStream();
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
            in.close();
            return bos.toString("UTF-8");
        } catch (Exception e) {
            return null;
        } finally {
            if (c != null) c.disconnect();
        }
    }
}
