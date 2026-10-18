package com.qvacloud.devmon.lite;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.hardware.Camera;
import android.os.Bundle;
import android.view.Gravity;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.Result;
import com.google.zxing.common.HybridBinarizer;

import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/** Escaner de QR con la camara + ZXing core (sin AndroidX). */
@SuppressWarnings("deprecation")
public class ScanActivity extends Activity implements SurfaceHolder.Callback, Camera.PreviewCallback {

    private static final int REQ_CAM = 10;

    private SurfaceView surface;
    private SurfaceHolder holder;
    private Camera camera;
    private MultiFormatReader reader;
    private volatile boolean done;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);

        Map<DecodeHintType, Object> hints = new EnumMap<>(DecodeHintType.class);
        hints.put(DecodeHintType.TRY_HARDER, Boolean.TRUE);
        reader = new MultiFormatReader();
        reader.setHints(hints);

        FrameLayout root = new FrameLayout(this);

        surface = new SurfaceView(this);
        holder = surface.getHolder();
        holder.addCallback(this);
        root.addView(surface, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        LinearLayout overlay = new LinearLayout(this);
        overlay.setOrientation(LinearLayout.VERTICAL);
        overlay.setGravity(Gravity.CENTER_HORIZONTAL);
        overlay.setPadding(32, 64, 32, 32);

        TextView title = new TextView(this);
        title.setText("Apunta al QR del agente");
        title.setTextColor(0xFF39FF14);
        title.setTextSize(18);
        title.setGravity(Gravity.CENTER);
        overlay.addView(title);

        TextView sub = new TextView(this);
        sub.setText("Manten el movil a unos 20 cm del QR que muestra el equipo.");
        sub.setTextColor(0xFFBFF5BF);
        sub.setTextSize(13);
        sub.setGravity(Gravity.CENTER);
        sub.setPadding(0, 12, 0, 0);
        overlay.addView(sub);

        Button cancel = new Button(this);
        cancel.setText("Cancelar");
        cancel.setAllCaps(false);
        cancel.setOnClickListener(v -> { setResult(RESULT_CANCELED); finish(); });
        LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        clp.topMargin = 24;
        overlay.addView(cancel, clp);

        root.addView(overlay, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP));

        setContentView(root);

        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.CAMERA}, REQ_CAM);
        }
    }

    @Override
    public void onRequestPermissionsResult(int req, String[] perms, int[] res) {
        super.onRequestPermissionsResult(req, perms, res);
        if (req == REQ_CAM) {
            if (res.length > 0 && res[0] == PackageManager.PERMISSION_GRANTED) {
                if (holder.getSurface() != null) startCamera();
            } else {
                Toast.makeText(this, "Necesito la camara para escanear el QR", Toast.LENGTH_LONG).show();
                finish();
            }
        }
    }

    @Override
    public void surfaceCreated(SurfaceHolder h) {
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        }
    }

    @Override public void surfaceChanged(SurfaceHolder h, int f, int w, int hh) { }
    @Override public void surfaceDestroyed(SurfaceHolder h) { stopCamera(); }

    @Override
    protected void onResume() {
        super.onResume();
        if (camera == null && holder.getSurface() != null
                && checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        stopCamera();
    }

    private void startCamera() {
        try {
            camera = Camera.open();
            if (camera == null) return;
            camera.setDisplayOrientation(90);
            Camera.Parameters p = camera.getParameters();
            p.setPreviewFormat(android.graphics.ImageFormat.NV21);
            Camera.Size best = null;
            List<Camera.Size> sizes = p.getSupportedPreviewSizes();
            for (Camera.Size s : sizes) {
                if (s.width >= 640 && (best == null || s.width < best.width)) best = s;
            }
            if (best == null && sizes != null && !sizes.isEmpty()) best = sizes.get(0);
            if (best != null) p.setPreviewSize(best.width, best.height);
            camera.setParameters(p);
            camera.setPreviewDisplay(holder);
            camera.setPreviewCallback(this);
            camera.startPreview();
        } catch (Exception e) {
            Toast.makeText(this, "No se pudo abrir la camara", Toast.LENGTH_LONG).show();
            stopCamera();
        }
    }

    private void stopCamera() {
        if (camera != null) {
            try {
                camera.setPreviewCallback(null);
                camera.stopPreview();
                camera.release();
            } catch (Exception ignored) { }
            camera = null;
        }
    }

    @Override
    public void onPreviewFrame(byte[] data, Camera cam) {
        if (done || data == null || camera == null) return;
        Camera.Size size = camera.getParameters().getPreviewSize();
        try {
            PlanarYUVLuminanceSource src = new PlanarYUVLuminanceSource(
                    data, size.width, size.height, 0, 0, size.width, size.height, false);
            BinaryBitmap bmp = new BinaryBitmap(new HybridBinarizer(src));
            Result r = reader.decodeWithState(bmp);
            if (r != null && r.getText() != null) {
                done = true;
                final String text = r.getText();
                runOnUiThread(() -> {
                    Intent out = new Intent();
                    out.putExtra("link", text);
                    setResult(RESULT_OK, out);
                    finish();
                });
            }
        } catch (Exception ignored) {
            // no encontrado en este frame: seguimos
        } finally {
            reader.reset();
        }
    }
}
