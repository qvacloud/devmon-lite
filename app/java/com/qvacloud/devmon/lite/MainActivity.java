package com.qvacloud.devmon.lite;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {

    private static final int REQ_SCAN = 1;
    private static final int REQ_PERMS = 2;
    private static final long POLL_MS = 5000;

    private static final int BG = Color.parseColor("#000000");
    private static final int CARD = Color.parseColor("#0b0f0b");
    private static final int ACCENT = Color.parseColor("#39FF14");
    private static final int RED = Color.parseColor("#ff3b30");
    private static final int TEXT = Color.parseColor("#e8ffe8");
    private static final int DIM = Color.parseColor("#7a8f7a");

    private Store store;
    private Settings settings;
    private List<Device> devices;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService pool = Executors.newFixedThreadPool(4);

    private LinearLayout listContainer;
    private TextView emptyHint;
    private boolean polling = true;
    private boolean structureDirty = true;
    private final Map<String, Card> cards = new HashMap<>();

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        store = new Store(this);
        settings = new Settings(this);
        devices = store.load();

        buildUi();
        Alerts.ensureChannel(this);
        requestBasePermissions();

        if (getIntent() != null && getIntent().getData() != null) {
            maybeAddFromUri(getIntent().getData());
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        if (intent != null && intent.getData() != null) maybeAddFromUri(intent.getData());
    }

    @Override
    protected void onResume() {
        super.onResume();
        applyKeepScreenOn();
        polling = true;
        ui.post(pollLoop);
    }

    @Override
    protected void onPause() {
        super.onPause();
        polling = false;
        ui.removeCallbacks(pollLoop);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        pool.shutdownNow();
    }

    // ------------------------------------------------------------------ UI

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        int pad = dp(16);
        root.setPadding(pad, pad, pad, pad);

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = new TextView(this);
        title.setText("device-monitor lite");
        title.setTextColor(ACCENT);
        title.setTextSize(19);
        title.setLayoutParams(new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        Button gear = new Button(this);
        gear.setText("Ajustes");
        gear.setAllCaps(false);
        gear.setOnClickListener(v -> showSettings());
        header.addView(title);
        header.addView(gear);
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        scroll.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        listContainer = new LinearLayout(this);
        listContainer.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(listContainer);
        root.addView(scroll);

        emptyHint = new TextView(this);
        emptyHint.setTextColor(DIM);
        emptyHint.setTextSize(14);
        emptyHint.setPadding(0, dp(24), 0, dp(24));
        emptyHint.setText("Aun no vigilas ningun equipo.\n\n1) Instala el agente en tu PC (Windows o Linux).\n"
                + "2) Pulsa \"Anadir equipo\" y escanea el QR que muestra.\n");
        listContainer.addView(emptyHint);

        Button add = new Button(this);
        add.setText("+  Anadir equipo");
        add.setAllCaps(false);
        add.setOnClickListener(v -> showAddDialog());
        root.addView(add);

        setContentView(root);
    }

    private void applyKeepScreenOn() {
        if (settings.keepScreenOn()) {
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        } else {
            getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
    }

    private void render() {
        if (structureDirty) {
            rebuild();
            structureDirty = false;
        }
        updateCards();
    }

    /** Reconstruye las tarjetas (solo cuando cambia la lista de equipos). */
    private void rebuild() {
        listContainer.removeAllViews();
        cards.clear();
        if (devices.isEmpty()) {
            listContainer.addView(emptyHint);
            return;
        }
        for (Device d : devices) {
            Card c = buildCard(d);
            cards.put(d.id, c);
            listContainer.addView(c.root);
        }
    }

    /** Refresca textos y colores sin tocar la estructura (no reinicia el scroll). */
    private void updateCards() {
        for (Device d : devices) {
            Card c = cards.get(d.id);
            if (c == null) continue;
            boolean online = d.online;
            int statusColor = online ? ACCENT : (d.known ? RED : DIM);
            c.dot.setBackground(circle(statusColor));
            c.state.setTextColor(statusColor);
            c.state.setText(online ? "En linea" : (d.known ? "Caido" : "Conectando..."));
            c.detail.setText(describe(d));
        }
    }

    private Card buildCard(Device d) {
        Card c = new Card();
        c.root = new LinearLayout(this);
        c.root.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, 0, 0, dp(12));
        c.root.setLayoutParams(lp);
        c.root.setBackground(roundRect(CARD, dp(14)));
        c.root.setPadding(dp(16), dp(14), dp(16), dp(14));

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);

        c.dot = new View(this);
        LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(dp(12), dp(12));
        dlp.setMargins(0, 0, dp(10), 0);
        c.dot.setLayoutParams(dlp);

        TextView name = new TextView(this);
        name.setText(d.name);
        name.setTextColor(TEXT);
        name.setTextSize(17);
        name.setLayoutParams(new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        c.state = new TextView(this);
        c.state.setTextSize(13);

        row.addView(c.dot);
        row.addView(name);
        row.addView(c.state);
        c.root.addView(row);

        c.detail = new TextView(this);
        c.detail.setTextColor(DIM);
        c.detail.setTextSize(13);
        c.detail.setPadding(0, dp(8), 0, 0);
        c.root.addView(c.detail);

        c.root.setOnLongClickListener(v -> { showDeviceMenu(d); return true; });
        return c;
    }

    private static class Card {
        LinearLayout root;
        View dot;
        TextView state;
        TextView detail;
    }

    private String describe(Device d) {
        Metrics m = d.metrics;
        StringBuilder sb = new StringBuilder();
        if (d.online && m != null) {
            sb.append("CPU ").append(Math.round(m.cpu)).append("%");
            sb.append("  RAM ").append(Math.round(m.memPercent)).append("%");
            if (m.temp != null) sb.append("  ").append(Math.round(m.temp)).append(" C");
            if (!m.diskLabel.isEmpty())
                sb.append("  Disco ").append(m.diskLabel).append(" ").append(Math.round(m.diskPercent)).append("%");
            sb.append("\nEncendido ").append(fmtUptime(m.uptimeSec));
            if (d.lastDownMs > 0)
                sb.append("  ·  ultima caida ").append(fmtDur(d.lastDownMs));
        } else if (d.downSince > 0) {
            sb.append("Sin respuesta desde hace ").append(fmtDur(System.currentTimeMillis() - d.downSince));
            sb.append("\n").append(d.baseUrl);
        } else if (d.known) {
            sb.append("No se pudo conectar.\n").append(d.baseUrl);
        } else {
            sb.append(d.baseUrl);
        }
        return sb.toString();
    }

    // -------------------------------------------------------------- dialogos

    private void showAddDialog() {
        LinearLayout box = dialogBox();
        TextView hint = new TextView(this);
        hint.setTextColor(DIM);
        hint.setTextSize(13);
        hint.setText("Escanea el QR del agente, o pega aqui el enlace del equipo.");
        box.addView(hint);

        EditText input = new EditText(this);
        input.setHint("devmon://add?n=...&u=http://192.168.1.20:55555&t=...");
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        box.addView(input);

        new AlertDialog.Builder(this)
                .setTitle("Anadir equipo")
                .setView(box)
                .setPositiveButton("Anadir", (x, y) -> {
                    Device d = Protocol.parse(input.getText().toString());
                    if (d == null) {
                        toast("Enlace no valido");
                    } else {
                        addDevice(d);
                    }
                })
                .setNeutralButton("Escanear QR", (x, y) -> startScan())
                .setNegativeButton("Cancelar", null)
                .show();
    }

    private void showDeviceMenu(Device d) {
        String[] opts = {"Renombrar", "Editar enlace/token", "Eliminar"};
        new AlertDialog.Builder(this)
                .setTitle(d.name)
                .setItems(opts, (dlg, which) -> {
                    if (which == 0) renameDevice(d);
                    else if (which == 1) editDevice(d);
                    else confirmDelete(d);
                })
                .show();
    }

    private void renameDevice(Device d) {
        EditText in = new EditText(this);
        in.setText(d.name);
        new AlertDialog.Builder(this)
                .setTitle("Renombrar")
                .setView(in)
                .setPositiveButton("Guardar", (x, y) -> {
                    String v = in.getText().toString().trim();
                    if (!v.isEmpty()) { d.name = v; persist(); }
                })
                .setNegativeButton("Cancelar", null)
                .show();
    }

    private void editDevice(Device d) {
        LinearLayout box = dialogBox();
        EditText url = new EditText(this);
        url.setHint("http://192.168.1.20:55555");
        url.setText(d.baseUrl);
        EditText tok = new EditText(this);
        tok.setHint("token (opcional)");
        tok.setText(d.token);
        box.addView(url);
        box.addView(tok);
        new AlertDialog.Builder(this)
                .setTitle("Editar equipo")
                .setView(box)
                .setPositiveButton("Guardar", (x, y) -> {
                    d.baseUrl = Device.stripSlash(url.getText().toString());
                    d.token = tok.getText().toString().trim();
                    persist();
                })
                .setNegativeButton("Cancelar", null)
                .show();
    }

    private void confirmDelete(Device d) {
        new AlertDialog.Builder(this)
                .setTitle("Eliminar")
                .setMessage("Dejar de vigilar \"" + d.name + "\"?")
                .setPositiveButton("Eliminar", (x, y) -> {
                    devices.remove(d);
                    persist();
                })
                .setNegativeButton("Cancelar", null)
                .show();
    }

    private void showSettings() {
        LinearLayout box = dialogBox();

        CheckBox screen = new CheckBox(this);
        screen.setText("Mantener la pantalla siempre encendida");
        screen.setTextColor(TEXT);
        screen.setChecked(settings.keepScreenOn());
        box.addView(screen);

        CheckBox alerts = new CheckBox(this);
        alerts.setText("Avisar de caidas y umbrales");
        alerts.setTextColor(TEXT);
        alerts.setChecked(settings.alertsEnabled());
        box.addView(alerts);

        TextView l1 = label("Avisar si CPU supera (%)");
        EditText cpu = num(String.valueOf(Math.round(settings.cpuThreshold())));
        TextView l2 = label("Avisar si memoria supera (%)");
        EditText mem = num(String.valueOf(Math.round(settings.memThreshold())));
        TextView l3 = label("Avisar si temperatura supera (C)");
        EditText temp = num(String.valueOf(Math.round(settings.tempThreshold())));
        TextView l4 = label("Avisar si disco supera (%)");
        EditText disk = num(String.valueOf(Math.round(settings.diskThreshold())));
        for (View v : new View[]{l1, cpu, l2, mem, l3, temp, l4, disk}) box.addView(v);

        new AlertDialog.Builder(this)
                .setTitle("Ajustes")
                .setView(box)
                .setPositiveButton("Guardar", (x, y) -> {
                    settings.setKeepScreenOn(screen.isChecked());
                    settings.setAlertsEnabled(alerts.isChecked());
                    settings.setThresholds(parse(cpu, 90), parse(mem, 90), parse(temp, 80), parse(disk, 90));
                    applyKeepScreenOn();
                })
                .setNegativeButton("Cerrar", null)
                .show();
    }

    // --------------------------------------------------------------- datos

    private void addDevice(Device d) {
        for (Device e : devices) {
            if (e.baseUrl.equalsIgnoreCase(d.baseUrl)) {
                toast("Ese equipo ya esta en la lista");
                return;
            }
        }
        devices.add(d);
        persist();
        toast("Equipo anadido");
    }

    private void persist() {
        store.save(devices);
        structureDirty = true;
        render();
    }

    private void maybeAddFromUri(Uri uri) {
        if (uri == null) return;
        Device d = Protocol.parse(uri.toString());
        if (d != null) addDevice(d);
    }

    // -------------------------------------------------------------- polling

    private final Runnable pollLoop = new Runnable() {
        @Override
        public void run() {
            if (!polling) return;
            final List<Device> snap = devices;
            for (final Device d : snap) {
                pool.execute(() -> pollOne(d));
            }
            ui.postDelayed(this, POLL_MS);
        }
    };

    private void pollOne(Device d) {
        String body = Net.fetchMetrics(d);
        long now = System.currentTimeMillis();
        boolean wasOnline = d.online;

        if (body != null) {
            try {
                d.metrics = Metrics.parse(new JSONObject(body));
            } catch (Exception e) {
                d.metrics = null;
            }
            d.lastSeen = now;
            d.known = true;
            if (!wasOnline && d.downSince > 0) {
                d.lastDownMs = now - d.downSince;
                if (settings.alertsEnabled())
                    Alerts.notify(this, d.id.hashCode(), d.name + " vuelve a estar en linea",
                            "Estuvo caido " + fmtDur(d.lastDownMs) + ".");
            }
            d.online = true;
            d.downSince = 0;
        } else {
            if (wasOnline) {
                d.downSince = now;
                if (settings.alertsEnabled())
                    Alerts.notify(this, d.id.hashCode(), d.name + " se ha caido",
                            "Dejo de responder. Sigue vigilando...");
            }
            d.online = false;
            d.known = true;
        }

        checkThresholds(d, now);
        ui.post(this::render);
    }

    private void checkThresholds(Device d, long now) {
        if (!settings.alertsEnabled() || !d.online || d.metrics == null) return;
        long cooldown = settings.alertCooldownMin() * 60_000L;
        if (now - d.lastAlertAt < cooldown) return;

        String msg = null;
        Metrics m = d.metrics;
        if (m.cpu > settings.cpuThreshold())
            msg = "CPU al " + Math.round(m.cpu) + "% (limite " + Math.round(settings.cpuThreshold()) + "%)";
        else if (m.memPercent > settings.memThreshold())
            msg = "Memoria al " + Math.round(m.memPercent) + "%";
        else if (m.temp != null && m.temp > settings.tempThreshold())
            msg = "Temperatura a " + Math.round(m.temp) + " C";
        else if (m.diskPercent > settings.diskThreshold())
            msg = "Disco " + m.diskLabel + " al " + Math.round(m.diskPercent) + "%";

        if (msg != null) {
            d.lastAlertAt = now;
            Alerts.notify(this, (d.id + ":th").hashCode(), d.name + ": " + msg, msg);
        }
    }

    // --------------------------------------------------------------- util

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == REQ_SCAN && res == RESULT_OK && data != null) {
            String link = data.getStringExtra("link");
            Device d = Protocol.parse(link);
            if (d != null) addDevice(d);
            else toast("Ese QR no es de device-monitor");
        }
    }

    private void startScan() {
        startActivityForResult(new Intent(this, ScanActivity.class), REQ_SCAN);
    }

    private void requestBasePermissions() {
        java.util.ArrayList<String> need = new java.util.ArrayList<>();
        if (checkSelfPermission(android.Manifest.permission.CAMERA)
                != android.content.pm.PackageManager.PERMISSION_GRANTED)
            need.add(android.Manifest.permission.CAMERA);
        if (android.os.Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != android.content.pm.PackageManager.PERMISSION_GRANTED)
            need.add(android.Manifest.permission.POST_NOTIFICATIONS);
        if (!need.isEmpty())
            requestPermissions(need.toArray(new String[0]), REQ_PERMS);
    }

    // --- helpers de vista/valores ---

    private LinearLayout dialogBox() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(20), dp(8), dp(20), dp(4));
        return box;
    }

    private TextView label(String s) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(DIM);
        t.setTextSize(13);
        t.setPadding(0, dp(8), 0, 0);
        return t;
    }

    private EditText num(String v) {
        EditText e = new EditText(this);
        e.setInputType(InputType.TYPE_CLASS_NUMBER);
        e.setText(v);
        return e;
    }

    private double parse(EditText e, double def) {
        try { return Double.parseDouble(e.getText().toString().trim()); }
        catch (Exception ex) { return def; }
    }

    static GradientDrawable roundRect(int color, int radius) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(radius);
        return g;
    }

    static GradientDrawable circle(int color) {
        GradientDrawable g = new GradientDrawable();
        g.setShape(GradientDrawable.OVAL);
        g.setColor(color);
        return g;
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private void toast(String s) {
        Toast.makeText(this, s, Toast.LENGTH_SHORT).show();
    }

    static String fmtBytes(long n) {
        String[] u = {"B", "KB", "MB", "GB", "TB"};
        double v = n;
        int i = 0;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (v >= 10 || i == 0 ? String.valueOf(Math.round(v)) : String.format("%.1f", v)) + " " + u[i];
    }

    static String fmtUptime(double s) {
        long t = (long) s;
        long d = t / 86400, h = (t % 86400) / 3600, m = (t % 3600) / 60;
        if (d > 0) return d + "d " + h + "h";
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    static String fmtDur(long ms) {
        long s = ms / 1000;
        if (s < 60) return s + "s";
        long m = s / 60;
        if (m < 60) return m + " min";
        long h = m / 60;
        if (h < 24) return h + "h " + (m % 60) + "m";
        return (h / 24) + "d " + (h % 24) + "h";
    }
}
