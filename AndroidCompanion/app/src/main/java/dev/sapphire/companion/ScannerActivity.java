package dev.sapphire.companion;

import android.app.*;
import android.content.Intent;
import android.hardware.Camera;
import android.os.*;
import android.view.*;
import android.widget.*;

import com.google.zxing.*;
import com.google.zxing.common.HybridBinarizer;

import java.util.*;
import java.util.concurrent.*;

/**
 * Offline QR scanner. Camera frames are never stored or sent over the network.
 */
@SuppressWarnings("deprecation")
public final class ScannerActivity extends Activity implements SurfaceHolder.Callback {
    private Camera camera;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final java.util.concurrent.atomic.AtomicBoolean decoding = new java.util.concurrent.atomic.AtomicBoolean();
    private volatile boolean finished;

    @Override
    public void onCreate(Bundle saved) {
        super.onCreate(saved);
        SurfaceView preview = new SurfaceView(this);
        preview.getHolder().addCallback(this);
        setContentView(preview);
        Toast.makeText(this, "Point the camera at Sapphire’s pairing QR code.", Toast.LENGTH_LONG).show();
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        try {
            camera = Camera.open();
            camera.setDisplayOrientation(90);
            camera.setPreviewDisplay(holder);
            Camera.Parameters p = camera.getParameters();
            if (p.getSupportedFocusModes().contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE))
                p.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE);
            camera.setParameters(p);
            camera.setPreviewCallback((data, c) -> {
                if (finished || !decoding.compareAndSet(false, true)) return;
                Camera.Size size = c.getParameters().getPreviewSize();
                byte[] copy = Arrays.copyOf(data, size.width * size.height);
                worker.execute(() -> {
                    try {
                        MultiFormatReader reader = new MultiFormatReader();
                        reader.setHints(Map.of(DecodeHintType.POSSIBLE_FORMATS, List.of(BarcodeFormat.QR_CODE), DecodeHintType.TRY_HARDER, true));
                        Result result = reader.decodeWithState(new BinaryBitmap(new HybridBinarizer(new PlanarYUVLuminanceSource(copy, size.width, size.height, 0, 0, size.width, size.height, false))));
                        String text = result.getText();
                        if (text.length() <= 8192 && !finished) {
                            finished = true;
                            runOnUiThread(() -> {
                                setResult(RESULT_OK, new Intent().putExtra("qr", text));
                                finish();
                            });
                        }
                    } catch (Exception ignored) {
                    } finally {
                        decoding.set(false);
                    }
                });
            });
            camera.startPreview();
        } catch (Exception e) {
            Toast.makeText(this, "Camera could not start. You can paste the pairing text instead.", Toast.LENGTH_LONG).show();
            finish();
        }
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        close();
    }

    private void close() {
        finished = true;
        if (camera != null) {
            camera.setPreviewCallback(null);
            camera.stopPreview();
            camera.release();
            camera = null;
        }
    }

    @Override
    protected void onDestroy() {
        close();
        worker.shutdownNow();
        super.onDestroy();
    }
}
