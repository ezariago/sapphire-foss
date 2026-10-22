package dev.sapphire.companion;

import android.Manifest;
import android.app.*;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.*;
import android.util.Base64;

import java.security.*;
import java.util.*;

import org.json.*;

import dev.sapphire.ipc.*;

/**
 * All protocol and connection state is confined to the main looper.
 */
public final class LinkService extends Service {
    static volatile LinkService instance;
    static final Set<Runnable> observers = new HashSet<>();
    private static final UUID SERVICE = UUID.fromString("DAB10001-5A50-434F-4D50-414E494F4E31"),
            INBOX = UUID.fromString("DAB10002-5A50-434F-4D50-414E494F4E31"), OUTBOX = UUID.fromString("DAB10003-5A50-434F-4D50-414E494F4E31"),
            CONTROL = UUID.fromString("DAB10004-5A50-434F-4D50-414E494F4E31"), CCC = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    final Handler main = new Handler(Looper.getMainLooper());
    String status = "Starting Bluetooth…", code = "", macName = "", hotspotStatus = "";
    boolean secure, pairingMode, localConfirmed;
    private BluetoothManager manager;
    private BluetoothGattServer server;
    private BluetoothLeAdvertiser advertiser;
    private BluetoothGattCharacteristic outbox;
    private BluetoothDevice peer;
    private int mtu = 23, messageId, epoch;
    private boolean subscribed, notificationPending, serviceReady;
    private String lastStatusPayload = "";
    private long lastStatusSent;
    private final ArrayDeque<byte[]> outgoing = new ArrayDeque<>();
    private GattFrames frames = new GattFrames();
    private JSONObject record, qr;
    private PairingStore store;
    private String deviceID;
    private KeyPair pairingKey;
    private byte[] pairingNonce, pendingLinkKey;
    private LinkCrypto.Session session;
    private long pairingExpires, lastReceived;
    private IHotspotHelper helper;
    private boolean helperBound;
    private final Set<ServiceConnection> helperConnections = new HashSet<>();
    private final AdvertiseCallback advertising = new AdvertiseCallback() {
        @Override
        public void onStartFailure(int error) {
            main.post(() -> setStatus("Bluetooth advertising failed. Turn Bluetooth on and retry (" + error + ")."));
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("phone-link", "Mac connection", NotificationManager.IMPORTANCE_LOW));
        startForeground(1, notification("Starting Bluetooth…"));
        store = new PairingStore(this);
        try {
            record = store.load();
            if (record != null) macName = record.getString("macName");
        } catch (Exception e) {
            setStatus("Saved pairing could not be unlocked. Forget it and pair again.");
        }
        deviceID = getSharedPreferences("settings", 0).getString("deviceID", null);
        if (deviceID == null) {
            deviceID = UUID.randomUUID().toString();
            getSharedPreferences("settings", 0).edit().putString("deviceID", deviceID).apply();
        }
        manager = getSystemService(BluetoothManager.class);
        openBluetooth();
        main.postDelayed(maintenance, 1000);
    }

    private Notification notification(String text) {
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(this, "phone-link").setSmallIcon(android.R.drawable.stat_sys_data_bluetooth).setContentTitle("Sapphire Companion").setContentText(text).setContentIntent(open).setOngoing(true).build();
    }

    private void trace(String event) {
        if ((getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0)
            return;
        android.util.Log.i("SapphireLink", event);
        // Developer readiness only: no peer IDs, clipboard, QR, keys or SAS digits.
        try (java.io.FileOutputStream out = new java.io.FileOutputStream(new java.io.File(getCacheDir(), "link-diagnostics.json"))) {
            out.write(LinkCrypto.utf8(object("processID", android.os.Process.myPid(), "event", event, "secure", secure, "pairing", pairingMode, "subscribed", subscribed,
                    "peerConnected", peer != null, "mtu", mtu, "queued", outgoing.size(), "hasCode", !code.isEmpty(), "hasSession", session != null).toString()));
        } catch (Exception ignored) {
        }
    }

    private void setStatus(String text) {
        status = text;
        getSystemService(NotificationManager.class).notify(1, notification(text));
        changed();
    }

    private void changed() {
        for (Runnable observer : new ArrayList<>(observers)) observer.run();
    }

    boolean clipboardEnabled() {
        return getSharedPreferences("settings", 0).getBoolean("clipboard", true);
    }

    private void openBluetooth() {
        try {
            if (manager == null || manager.getAdapter() == null || !manager.getAdapter().isEnabled()) {
                setStatus("Turn on Bluetooth, then tap Start connection.");
                return;
            }
            server = manager.openGattServer(this, gatt);
            if (server == null) throw new IllegalStateException();
            BluetoothGattService service = new BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY);
            service.addCharacteristic(new BluetoothGattCharacteristic(INBOX, BluetoothGattCharacteristic.PROPERTY_WRITE, BluetoothGattCharacteristic.PERMISSION_WRITE));
            outbox = new BluetoothGattCharacteristic(OUTBOX, BluetoothGattCharacteristic.PROPERTY_NOTIFY | BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ);
            outbox.addDescriptor(new BluetoothGattDescriptor(CCC, BluetoothGattDescriptor.PERMISSION_READ | BluetoothGattDescriptor.PERMISSION_WRITE));
            service.addCharacteristic(outbox);
            service.addCharacteristic(new BluetoothGattCharacteristic(CONTROL, BluetoothGattCharacteristic.PROPERTY_WRITE, BluetoothGattCharacteristic.PERMISSION_WRITE));
            if (!server.addService(service)) throw new IllegalStateException();
        } catch (Exception e) {
            setStatus("Bluetooth could not start. Check Nearby devices permission and try again.");
        }
    }

    private void advertise() {
        if (!serviceReady || manager == null) return;
        try {
            if (advertiser != null) advertiser.stopAdvertising(advertising);
            advertiser = manager.getAdapter().getBluetoothLeAdvertiser();
            if (advertiser == null) throw new IllegalStateException();
            byte[] manufacturer = LinkCrypto.concat(new byte[]{1, 1}, Arrays.copyOf(LinkCrypto.hash(LinkCrypto.utf8(deviceID)), 8), new byte[]{0, 0, (byte) battery(), (byte) (pairingMode ? 1 : 0)});
            AdvertiseData data = new AdvertiseData.Builder().addServiceUuid(new ParcelUuid(SERVICE)).build();
            AdvertiseData response = new AdvertiseData.Builder().addManufacturerData(0xffff, manufacturer).build();
            advertiser.startAdvertising(new AdvertiseSettings.Builder().setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).setConnectable(true).setTimeout(0).build(), data, response, advertising);
            if (peer == null)
                setStatus(pairingMode ? "Ready to pair. Scan or paste the Mac’s QR code." : record == null ? "Tap Pair a Mac to begin." : "Waiting for " + macName + "…");
        } catch (Exception e) {
            setStatus("Could not advertise over Bluetooth. Turn Bluetooth on and retry.");
        }
    }

    private final BluetoothGattServerCallback gatt = new BluetoothGattServerCallback() {
        @Override
        public void onServiceAdded(int status, BluetoothGattService service) {
            main.post(() -> {
                serviceReady = status == BluetoothGatt.GATT_SUCCESS;
                if (serviceReady) advertise();
                else setStatus("Bluetooth service setup failed.");
            });
        }

        @Override
        public void onConnectionStateChange(BluetoothDevice device, int status, int state) {
            main.post(() -> {
                if (state == BluetoothProfile.STATE_CONNECTED) {
                    if (peer != null && !peer.equals(device)) {
                        server.cancelConnection(device);
                        return;
                    }
                    resetConnection();
                    peer = device;
                    trace("BLE connected");
                    setStatus("Mac connected. Waiting for authentication…");
                } else if (peer != null && peer.equals(device)) {
                    resetConnection();
                    peer = null;
                    advertise();
                }
            });
        }

        @Override
        public void onMtuChanged(BluetoothDevice device, int value) {
            main.post(() -> {
                if (device.equals(peer)) mtu = Math.max(23, Math.min(517, value));
            });
        }

        @Override
        public void onCharacteristicWriteRequest(BluetoothDevice device, int requestId, BluetoothGattCharacteristic characteristic, boolean prepared, boolean response, int offset, byte[] value) {
            byte[] copy = value.clone();
            main.post(() -> {
                boolean allowed = device.equals(peer) && !prepared && offset == 0 && (characteristic.getUuid().equals(INBOX) || characteristic.getUuid().equals(CONTROL));
                if (response)
                    server.sendResponse(device, requestId, allowed ? BluetoothGatt.GATT_SUCCESS : BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null);
                if (allowed) try {
                    byte[] data = frames.accept(copy, SystemClock.elapsedRealtime());
                    if (data != null) receive(data);
                } catch (Exception e) {
                    protocolFailure();
                }
            });
        }

        @Override
        public void onDescriptorWriteRequest(BluetoothDevice device, int requestId, BluetoothGattDescriptor descriptor, boolean prepared, boolean response, int offset, byte[] value) {
            main.post(() -> {
                boolean valid = device.equals(peer) && descriptor.getUuid().equals(CCC) && !prepared && offset == 0 && (Arrays.equals(value, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) || Arrays.equals(value, BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE));
                if (valid)
                    subscribed = Arrays.equals(value, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
                trace("Subscription valid=" + valid + " enabled=" + subscribed);
                if (response)
                    server.sendResponse(device, requestId, valid ? BluetoothGatt.GATT_SUCCESS : BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null);
                if (valid && subscribed) drain();
            });
        }

        @Override
        public void onDescriptorReadRequest(BluetoothDevice device, int requestId, int offset, BluetoothGattDescriptor descriptor) {
            main.post(() -> server.sendResponse(device, requestId, device.equals(peer) && offset == 0 ? BluetoothGatt.GATT_SUCCESS : BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, subscribed ? BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE : BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE));
        }

        @Override
        public void onCharacteristicReadRequest(BluetoothDevice device, int requestId, int offset, BluetoothGattCharacteristic characteristic) {
            main.post(() -> server.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null));
        }

        @Override
        public void onNotificationSent(BluetoothDevice device, int status) {
            main.post(() -> {
                if (!device.equals(peer)) return;
                notificationPending = false;
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    protocolFailure();
                    return;
                }
                drain();
            });
        }
    };

    private void resetConnection() {
        epoch++;
        secure = false;
        subscribed = false;
        session = null;
        mtu = 23;
        outgoing.clear();
        notificationPending = false;
        frames = new GattFrames();
        lastReceived = SystemClock.elapsedRealtime();
        changed();
    }

    private void protocolFailure() {
        setStatus("The Mac connection was interrupted or could not be verified. Reconnect or start pairing again.");
        if (peer != null && server != null) server.cancelConnection(peer);
        resetConnection();
    }

    private void drain() {
        if (peer == null || !subscribed || notificationPending || outgoing.isEmpty()) return;
        byte[] chunk = outgoing.removeFirst();
        notificationPending = true;
        try {
            boolean ok;
            if (Build.VERSION.SDK_INT >= 33)
                ok = server.notifyCharacteristicChanged(peer, outbox, false, chunk) == BluetoothStatusCodes.SUCCESS;
            else {
                outbox.setValue(chunk);
                ok = server.notifyCharacteristicChanged(peer, outbox, false);
            }
            if (!ok) {
                notificationPending = false;
                protocolFailure();
            }
        } catch (Exception e) {
            notificationPending = false;
            protocolFailure();
        }
    }

    private static String b64(byte[] b) {
        return Base64.encodeToString(b, Base64.NO_WRAP);
    }

    private static byte[] unb64(String s) {
        return Base64.decode(s, Base64.NO_WRAP);
    }

    private static JSONObject object(Object... values) {
        JSONObject j = new JSONObject();
        try {
            for (int i = 0; i < values.length; i += 2) j.put((String) values[i], values[i + 1]);
        } catch (JSONException e) {
            throw new IllegalArgumentException(e);
        }
        return j;
    }

    private void send(String type, JSONObject payload, boolean plaintext) {
        try {
            if (peer == null || !subscribed || (!plaintext && session == null)) return;
            JSONObject envelope = LinkEnvelope.encode(type, payload);
            byte[] data = LinkCrypto.utf8(envelope.toString());
            if (!plaintext) data = session.seal(data);
            trace("Send " + type + " bytes=" + data.length);
            List<byte[]> parts = GattFrames.split(data, ++messageId, Math.min(mtu - 3, 512));
            if (outgoing.size() + parts.size() > 512)
                throw new IllegalStateException("Backpressure");
            outgoing.addAll(parts);
            drain();
        } catch (Exception e) {
            protocolFailure();
        }
    }

    private void receive(byte[] frame) throws Exception {
        boolean encrypted = frame.length >= 4 && Arrays.equals(Arrays.copyOf(frame, 4), LinkCrypto.utf8("SBE1"));
        if (encrypted && session == null) throw new GeneralSecurityException();
        byte[] data = encrypted ? session.open(frame) : frame;
        JSONObject message = new JSONObject(new String(data, java.nio.charset.StandardCharsets.UTF_8));
        if (message.optInt("v", 1) != 1) throw new GeneralSecurityException();
        String type = message.getString("type");
        JSONObject p = message.optJSONObject("payload");
        if (p == null) p = new JSONObject();
        if (!encrypted && !Set.of("hello", "pair.result").contains(type)) return;
        if (!encrypted && secure) return;
        trace("Receive " + type + " encrypted=" + encrypted);
        lastReceived = SystemClock.elapsedRealtime();
        if (encrypted && !secure) {
            secure = true;
            setStatus("Connected securely to " + macName);
        }
        switch (type) {
            case "hello":
                if (pairingMode) {
                    if (qr != null && qr.getString("macDeviceId").equals(p.optString("deviceId")))
                        pairHello();
                    return;
                }
                if (record == null || !record.getString("macID").equals(p.optString("deviceId")))
                    return;
                JSONObject remote = p.getJSONObject("bleEncryption");
                if (remote.getInt("version") != 1) throw new GeneralSecurityException();
                byte[] macNonce = unb64(remote.getString("nonce")), phoneNonce = LinkCrypto.random(32);
                session = new LinkCrypto.Session(unb64(record.getString("linkKey")), macNonce, phoneNonce, true);
                send("hello", object("deviceId", deviceID, "deviceName", Build.MODEL, "deviceType", "android", "protocolVersion", 1, "bleEncryption", object("version", 1, "nonce", b64(phoneNonce))), true);
                setStatus("Verifying the encrypted Mac connection…");
                break;
            case "pair.result":
                if (!pairingMode || qr == null || !localConfirmed || !p.optBoolean("ok") || SystemClock.elapsedRealtime() > pairingExpires)
                    return;
                JSONObject next = object("macID", qr.getString("macDeviceId"), "macName", qr.getString("macName"), "linkKey", b64(pendingLinkKey));
                store.save(next);
                record = next;
                macName = next.getString("macName");
                clearPairing();
                advertise();
                setStatus("Paired. Waiting for the encrypted connection…");
                break;
            case "status.request":
            case "battery.request":
                sendDeviceStatus(true);
                break;
            case "media.request":
                send("media.state", object("isPlaying", false, "title", "", "artist", "", "durationMs", 0, "positionMs", 0), false);
                break;
            case "clipboard.update":
                if (clipboardEnabled() && "text".equals(p.optString("contentType"))) {
                    String text = p.optString("text", "");
                    if (!text.isEmpty() && LinkCrypto.utf8(text).length < 12000) {
                        ClipData clip = ClipData.newPlainText("Sapphire from Mac", text);
                        PersistableBundle extras = new PersistableBundle();
                        extras.putBoolean("dev.sapphire.fromMac", true);
                        clip.getDescription().setExtras(extras);
                        getSystemService(ClipboardManager.class).setPrimaryClip(clip);
                    }
                }
                break;
            case "hotspot.request":
                setHotspot(true);
                break;
            case "hotspot.stop":
                setHotspot(false);
                break;
            case "ping":
                send("pong", p, false);
                break;
            default:
                break;
        }
    }

    private void sendDeviceStatus(boolean force) {
        if (!secure) return;
        JSONObject payload = PhoneStatus.read(this);
        String encoded = payload.toString();
        long now = SystemClock.elapsedRealtime();
        if (force || !encoded.equals(lastStatusPayload) || now - lastStatusSent >= 20000) {
            send("status.device", payload, false);
            lastStatusPayload = encoded;
            lastStatusSent = now;
        }
    }

    private int battery() {
        Intent i = registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        return i == null ? 0 : Math.max(0, Math.min(100, 100 * i.getIntExtra(BatteryManager.EXTRA_LEVEL, 0) / Math.max(1, i.getIntExtra(BatteryManager.EXTRA_SCALE, 100))));
    }

    private void pairHello() {
        trace("Pair reply ready=" + (qr != null && pendingLinkKey != null) + " peer=" + (peer != null) + " subscribed=" + subscribed);
        if (qr == null || pendingLinkKey == null || peer == null || !subscribed) return;
        send("pair.hello", object("deviceId", deviceID, "deviceName", Build.MODEL, "ecdhPublicKey", b64(LinkCrypto.publicPoint(pairingKey.getPublic())), "nonce", b64(pairingNonce)), true);
    }

    private final Runnable maintenance = new Runnable() {
        public void run() {
            if (pairingMode && qr != null) {
                if (SystemClock.elapsedRealtime() > pairingExpires) {
                    clearPairing();
                    setStatus("Pairing expired. Scan a fresh Mac code.");
                    advertise();
                } else pairHello();
            }
            if (peer != null && SystemClock.elapsedRealtime() - lastReceived > 90000) {
                if (server != null) server.cancelConnection(peer);
                resetConnection();
                peer = null;
                advertise();
            }
            sendDeviceStatus(false);
            main.postDelayed(this, 2000);
        }
    };

    private void beginPairing() {
        if (peer != null) server.cancelConnection(peer);
        resetConnection();
        peer = null;
        clearPairing();
        pairingMode = true;
        advertise();
    }

    private void clearPairing() {
        pairingMode = false;
        qr = null;
        pairingKey = null;
        pairingNonce = null;
        pendingLinkKey = null;
        code = "";
        localConfirmed = false;
        changed();
    }

    private void importQR(String encoded) {
        try {
            if (encoded == null || encoded.length() > 8192) throw new IllegalArgumentException();
            JSONObject candidate = new JSONObject(new String(unb64(encoded.trim()), java.nio.charset.StandardCharsets.UTF_8));
            if (candidate.getInt("v") != 1 || candidate.getString("macDeviceId").length() > 200 || candidate.getString("macDeviceId").isEmpty() || candidate.getString("macName").length() > 200)
                throw new IllegalArgumentException();
            byte[] macPublic = unb64(candidate.getString("ecdhPublicKey")), macNonce = unb64(candidate.getString("nonce"));
            if (macNonce.length != 16) throw new IllegalArgumentException();
            // A new challenge can only be imported in the local pairing UI. Do not
            // silently switch a currently authenticated connection into pairing.
            if (!pairingMode) beginPairing();
            pairingKey = LinkCrypto.keyPair();
            pairingNonce = LinkCrypto.random(16);
            byte[] shared = LinkCrypto.shared(pairingKey.getPrivate(), macPublic), salt = LinkCrypto.concat(macNonce, pairingNonce);
            pendingLinkKey = LinkCrypto.hkdf(shared, salt, "sapphire-continuity-link", 32);
            code = LinkCrypto.sas(shared, salt);
            qr = candidate;
            localConfirmed = false;
            pairingExpires = SystemClock.elapsedRealtime() + 180000;
            setStatus("Compare the six digits on both devices. Confirm only if they match.");
            pairHello();
        } catch (Exception e) {
            clearPairing();
            setStatus("This is not a valid Sapphire pairing code. Show a new Mac code and try again.");
            advertise();
        }
    }

    void sendClipboardFromActivity() {
        if (!secure) return;
        ClipboardManager clipboard = getSystemService(ClipboardManager.class);
        ClipData clip = clipboard.getPrimaryClip();
        if (clip == null || clip.getItemCount() != 1) return;
        PersistableBundle extras = clip.getDescription().getExtras();
        if (extras != null && (extras.getBoolean("android.content.extra.IS_SENSITIVE", false) || extras.getBoolean("dev.sapphire.fromMac", false)))
            return;
        CharSequence value = clip.getItemAt(0).getText();
        if (value == null) return;
        String text = value.toString();
        if (!text.isEmpty() && LinkCrypto.utf8(text).length < 12000)
            send("clipboard.update", object("contentType", "text", "text", text), false);
    }

    private void setHotspot(boolean enabled) {
        if (!secure) return;
        if (!getSharedPreferences("settings", 0).getBoolean("hotspot", true)) {
            send("hotspot.status", object("state", "denied", "message", "Enable Mac hotspot control in Sapphire Companion."), false);
            return;
        }
        final int requestEpoch = epoch;
        send("hotspot.status", object("state", "starting", "mode", "internet"), false);
        final AtomicBooleanResult done = new AtomicBooleanResult();
        final ServiceConnection connection = new ServiceConnection() {
            @Override
            public void onServiceConnected(ComponentName name, IBinder binder) {
                ServiceConnection owner = this;
                try {
                    IHotspotHelper.Stub.asInterface(binder).setEnabled(enabled, new IHotspotCallback.Stub() {
                        public void onResult(Bundle result) {
                            main.post(() -> {
                                if (done.finish()) {
                                    release(owner);
                                    handleHotspotResult(result, requestEpoch);
                                }
                            });
                        }
                    });
                } catch (Exception e) {
                    failed();
                }
            }

            private void failed() {
                if (done.finish()) {
                    release(this);
                    handleHotspotResult(errorResult("needs_setup", "Install and authorize Sapphire Hotspot Helper."), requestEpoch);
                }
            }

            @Override
            public void onServiceDisconnected(ComponentName name) {
                failed();
            }

            @Override
            public void onNullBinding(ComponentName name) {
                failed();
            }

            @Override
            public void onBindingDied(ComponentName name) {
                failed();
            }
        };
        helperConnections.add(connection);
        try {
            boolean bound = bindService(new Intent().setComponent(new ComponentName("dev.sapphire.companion.hotspothelper", "dev.sapphire.helper.HotspotService")), connection, BIND_AUTO_CREATE);
            if (!bound) {
                done.finish();
                release(connection);
                handleHotspotResult(errorResult("needs_setup", "Install Sapphire Hotspot Helper and authorize it in Shizuku."), requestEpoch);
            }
        } catch (Exception e) {
            done.finish();
            release(connection);
            handleHotspotResult(errorResult("needs_setup", "The helper is missing or its signature does not match."), requestEpoch);
        }
        main.postDelayed(() -> {
            if (done.finish()) {
                release(connection);
                handleHotspotResult(errorResult("error", "The hotspot request timed out. Check the helper app."), requestEpoch);
            }
        }, 35000);
    }

    private static final class AtomicBooleanResult {
        private final java.util.concurrent.atomic.AtomicBoolean done = new java.util.concurrent.atomic.AtomicBoolean();

        boolean finish() {
            return done.compareAndSet(false, true);
        }
    }

    private static Bundle errorResult(String state, String message) {
        Bundle b = new Bundle();
        b.putString("state", state);
        b.putString("message", message);
        return b;
    }

    private void release(ServiceConnection connection) {
        helperConnections.remove(connection);
        try {
            unbindService(connection);
        } catch (Exception ignored) {
        }
    }

    private void handleHotspotResult(Bundle result, int requestEpoch) {
        hotspotStatus = result.getString("message", result.getString("state", "Unknown hotspot status"));
        changed();
        if (!secure || epoch != requestEpoch) return;
        if ("active".equals(result.getString("state")) && result.containsKey("passphrase"))
            send("hotspot.credentials", object("ssid", result.getString("ssid"), "passphrase", result.getString("passphrase"), "band", result.getString("band", "auto"), "security", result.getString("security"), "internet", true), false);
        send("hotspot.status", object("state", result.getString("state", "error"), "mode", "internet", "message", hotspotStatus), false);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int id) {
        if (intent != null) {
            String action = intent.getAction();
            if ("pair".equals(action)) beginPairing();
            else if ("qr".equals(action)) importQR(intent.getStringExtra("qr"));
            else if ("confirm".equals(action) && qr != null && !code.isEmpty() && SystemClock.elapsedRealtime() < pairingExpires) {
                localConfirmed = true;
                send("pair.confirm", object("sas", code), true);
                setStatus("Phone confirmed. Confirm the matching code on your Mac.");
            } else if ("forget".equals(action)) {
                if (peer != null) server.cancelConnection(peer);
                resetConnection();
                peer = null;
                store.clear();
                record = null;
                macName = "";
                clearPairing();
                advertise();
            } else if ("stop".equals(action)) {
                stopSelf();
                return START_NOT_STICKY;
            } else if (server == null) openBluetooth();
        }
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        main.removeCallbacksAndMessages(null);
        for (ServiceConnection c : new ArrayList<>(helperConnections)) release(c);
        try {
            if (advertiser != null) advertiser.stopAdvertising(advertising);
            if (server != null) server.close();
        } catch (Exception ignored) {
        }
        instance = null;
        observers.clear();
        super.onDestroy();
    }
}
