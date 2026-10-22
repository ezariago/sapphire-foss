package dev.sapphire.companion;

import android.app.*;
import android.content.*;
import android.os.*;

import java.util.*;
import java.util.concurrent.*;

import dev.sapphire.ipc.*;

import org.json.JSONObject;

/**
 * Opt-in developer checks; test APK is not part of either deliverable app.
 */
public final class DeviceChecks extends Instrumentation {
    private Bundle args;

    @Override
    public void onCreate(Bundle args) {
        this.args = args;
        start();
    }

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    @Override
    public void onStart() {
        Bundle result = new Bundle();
        try {
            java.security.KeyPair a = LinkCrypto.keyPair(), b = LinkCrypto.keyPair();
            byte[] shared = LinkCrypto.shared(a.getPrivate(), LinkCrypto.publicPoint(b.getPublic()));
            require(Arrays.equals(shared, LinkCrypto.shared(b.getPrivate(), LinkCrypto.publicPoint(a.getPublic()))), "Android ECDH");
            byte[] nonce = new byte[32];
            Arrays.fill(nonce, (byte) 7);
            LinkCrypto.Session mac = new LinkCrypto.Session(shared, new byte[32], nonce, false), phone = new LinkCrypto.Session(shared, new byte[32], nonce, true);
            byte[] message = LinkCrypto.utf8("Android provider check"), frame = mac.seal(message);
            require(Arrays.equals(message, phone.open(frame)), "Android ChaCha20-Poly1305");
            boolean replay = false;
            try {
                phone.open(frame);
            } catch (Exception expected) {
                replay = true;
            }
            require(replay, "Android replay rejection");
            GattFrames parser = new GattFrames();
            byte[] complete = null;
            for (byte[] chunk : GattFrames.split(message, 1, 20)) {
                byte[] p = parser.accept(chunk, 0);
                if (p != null) complete = p;
            }
            require(Arrays.equals(message, complete), "Android fragment reconstruction");
            result.putBoolean("cryptoPassed", true);
            JSONObject status = PhoneStatus.read(getTargetContext());
            require(status.has("batteryPercent"), "Real device battery telemetry");
            require(status.optInt("signalLevel", -1) >= 0 && status.optInt("signalLevel", -1) <= 4, "Real modem signal telemetry");
            require(!status.optString("carrier").isEmpty(), "Real mobile provider telemetry");
            result.putBoolean("phoneTelemetryPassed", true);
            result.putInt("signalLevel", status.getInt("signalLevel"));
            result.putString("carrier", status.getString("carrier"));

            if ("true".equals(args.getString("hotspot"))) {
                Context context = getTargetContext();
                CountDownLatch connected = new CountDownLatch(1);
                IHotspotHelper[] helper = new IHotspotHelper[1];
                ServiceConnection connection = new ServiceConnection() {
                    public void onServiceConnected(ComponentName n, IBinder b) {
                        helper[0] = IHotspotHelper.Stub.asInterface(b);
                        connected.countDown();
                    }

                    public void onServiceDisconnected(ComponentName n) {
                    }
                };
                require(context.bindService(new Intent().setComponent(new ComponentName("dev.sapphire.companion.hotspothelper", "dev.sapphire.helper.HotspotService")), connection, Context.BIND_AUTO_CREATE), "Helper binding");
                try {
                    require(connected.await(10, TimeUnit.SECONDS) && helper[0] != null, "Helper startup");
                    Bundle enabled = operation(helper[0], true);
                    String state = enabled.getString("state", "");
                    result.putString("hotspotStartState", state);
                    result.putBoolean("credentialsReceived", enabled.containsKey("passphrase"));
                    result.putBoolean("internetMode", enabled.getBoolean("internet", false));
                    // Expose only readiness; never include SSID, passphrase or pairing data.
                    Bundle progress = new Bundle();
                    progress.putString("phase", "hotspot-started");
                    progress.putString("state", state);
                    sendStatus(0, progress);
                    if ("active".equals(state) || "configure".equals(state)) Thread.sleep(10000);
                    result.putBoolean("hotspotStarted", "active".equals(state) || "configure".equals(state));
                } finally {
                    if (helper[0] != null) {
                        Bundle stopped = operation(helper[0], false);
                        result.putString("hotspotStopState", stopped.getString("state", ""));
                    }
                    context.unbindService(connection);
                }
            }
            result.putString("result", "passed");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable e) {
            result.putString("result", "failed");
            result.putString("error", e.getClass().getSimpleName() + ": " + e.getMessage());
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private static Bundle operation(IHotspotHelper helper, boolean enabled) throws Exception {
        CountDownLatch received = new CountDownLatch(1);
        Bundle[] answer = new Bundle[1];
        helper.setEnabled(enabled, new IHotspotCallback.Stub() {
            public void onResult(Bundle result) {
                answer[0] = result;
                received.countDown();
            }
        });
        if (!received.await(35, TimeUnit.SECONDS))
            throw new IllegalStateException("Hotspot helper timed out");
        return answer[0];
    }
}
