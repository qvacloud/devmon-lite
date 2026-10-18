package com.qvacloud.devmon.lite;

import android.net.Uri;

/** Formato del enlace del QR: devmon://add?n=<nombre>&u=<url>&t=<token> */
public class Protocol {
    public static final String SCHEME = "devmon";

    public static Device parse(String raw) {
        if (raw == null) return null;
        String s = raw.trim();
        if (s.isEmpty()) return null;
        try {
            Uri u = Uri.parse(s);
            if (!SCHEME.equals(u.getScheme())) return null;
            String base = u.getQueryParameter("u");
            if (base == null || base.isEmpty()) return null;
            String n = u.getQueryParameter("n");
            String t = u.getQueryParameter("t");
            if (n == null || n.isEmpty()) n = "Equipo";
            return new Device(n, base, t == null ? "" : t);
        } catch (Exception e) {
            return null;
        }
    }
}
