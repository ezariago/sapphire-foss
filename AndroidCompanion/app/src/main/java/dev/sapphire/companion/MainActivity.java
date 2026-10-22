package dev.sapphire.companion;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.widget.*;

import java.util.*;

public final class MainActivity extends Activity {
    private TextView status, paired, code, hotspotStatus;
    private Button confirm;
    private EditText qr;
    private String permissionAction;
    private final Runnable observer = this::refresh;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable refreshLoop = new Runnable() {
        public void run() {
            refresh();
            main.postDelayed(this, 1000);
        }
    };

    @Override
    public void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN | WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        LinearLayout content = new LinearLayout(this);
        content.setFocusableInTouchMode(true);
        content.requestFocus();
        content.setOrientation(1);
        content.setPadding(28, 24, 28, 32);
        content.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(28, insets.getSystemWindowInsetTop() + 24, 28, insets.getSystemWindowInsetBottom() + 24);
            return insets;
        });
        title(content, "Sapphire Companion", 30);
        TextView sub = title(content, "Your phone, connected to your Mac", 16);
        sub.setTextColor(Color.LTGRAY);
        status = title(content, "Start the connection to begin.", 18);
        paired = title(content, "", 14);
        button(content, "Start connection", () -> ensureConnection(null));
        button(content, "Pair a Mac", () -> ensureConnection("pair"));
        code = title(content, "", 40);
        code.setTypeface(android.graphics.Typeface.MONOSPACE);
        confirm = button(content, "Codes match — confirm on phone", () -> new AlertDialog.Builder(this).setTitle("Do the codes match?").setMessage("Confirm only if these exact six digits also appear on your Mac. If the Mac shows no code, cancel and reconnect.").setNegativeButton("Cancel", null).setPositiveButton("Confirm matching codes", (d, w) -> send("confirm", null)).show());
        title(content, "Pair with a code", 22);
        title(content, "In Sapphire on your Mac, open Settings → Continuity → Pair a phone. Scan that QR code, or paste its pairing text below.", 15);
        button(content, "Scan Mac QR code", () -> {
            if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
                requestPermissions(new String[]{Manifest.permission.CAMERA}, 12);
            else startActivityForResult(new Intent(this, ScannerActivity.class), 20);
        });
        qr = new EditText(this);
        qr.setHint("Mac pairing text");
        qr.setSingleLine(false);
        qr.setMaxLines(3);
        qr.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        qr.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
        content.addView(qr);
        button(content, "Use pairing text", () -> {
            String text = qr.getText().toString().trim();
            if (!text.isEmpty()) {
                ensureConnection(null);
                main.postDelayed(() -> send("qr", text), 300);
                qr.setText("");
            }
        });
        title(content, "Clipboard", 22);
        Switch receive = new Switch(this);
        receive.setText("Receive Mac clipboard text");
        receive.setChecked(getSharedPreferences("settings", 0).getBoolean("clipboard", true));
        receive.setOnCheckedChangeListener((v, value) -> getSharedPreferences("settings", 0).edit().putBoolean("clipboard", value).apply());
        content.addView(receive);
        title(content, "New Mac text copies arrive automatically while connected. Android limits clipboard access in the background.", 14);
        button(content, "Send phone clipboard to Mac", () -> {
            if (LinkService.instance != null && LinkService.instance.secure)
                LinkService.instance.sendClipboardFromActivity();
            else Toast.makeText(this, "Connect to your Mac first.", Toast.LENGTH_SHORT).show();
        });
        title(content, "Mobile hotspot", 22);
        title(content, "Your paired Mac can start the phone’s real internet hotspot through Sapphire Hotspot Helper. On this Android version, the helper needs your Shizuku authorization. Mobile data and carrier support are required.", 14);
        Switch hotspot = new Switch(this);
        hotspot.setText("Allow paired Mac to control hotspot");
        hotspot.setChecked(getSharedPreferences("settings", 0).getBoolean("hotspot", true));
        hotspot.setOnCheckedChangeListener((v, value) -> getSharedPreferences("settings", 0).edit().putBoolean("hotspot", value).apply());
        content.addView(hotspot);
        hotspotStatus = title(content, "", 14);
        button(content, "Set up hotspot helper", () -> {
            try {
                startActivity(new Intent().setComponent(new ComponentName("dev.sapphire.companion.hotspothelper", "dev.sapphire.helper.HelperActivity")));
            } catch (Exception e) {
                new AlertDialog.Builder(this).setMessage("Install SapphireHotspotHelper.apk from the same build, then return here.").setPositiveButton("OK", null).show();
            }
        });
        button(content, "Android hotspot settings", () -> {
            try {
                startActivity(new Intent("android.settings.TETHER_SETTINGS"));
            } catch (Exception e) {
                startActivity(new Intent(Settings.ACTION_WIRELESS_SETTINGS));
            }
        });
        title(content, "This first version includes Bluetooth pairing, battery status, text clipboard and hotspot control. Media controls, notifications, files and screen sharing are not included yet.", 14);
        button(content, "Stop connection", () -> send("stop", null));
        button(content, "Forget this Mac", () -> new AlertDialog.Builder(this).setMessage("Remove this companion’s saved Mac pairing?").setNegativeButton("Cancel", null).setPositiveButton("Forget", (d, w) -> send("forget", null)).show());
        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        setContentView(scroll);
        if (getIntent().hasExtra("qr")) {
            String challenge = getIntent().getStringExtra("qr");
            getIntent().removeExtra("qr");
            qr.setText(challenge);
        }
        refresh();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        android.util.Log.i("SapphireLink", "Launcher QR extra=" + intent.hasExtra("qr"));
        setIntent(intent);
        if (intent.hasExtra("qr")) {
            qr.setText(intent.getStringExtra("qr"));
            intent.removeExtra("qr");
        }
    }

    private TextView title(LinearLayout content, String text, int size) {
        TextView v = new TextView(this);
        v.setText(text);
        v.setTextSize(size);
        v.setTextColor(Color.WHITE);
        v.setPadding(0, 18, 0, 10);
        content.addView(v);
        return v;
    }

    private Button button(LinearLayout content, String text, Runnable action) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setOnClickListener(v -> action.run());
        content.addView(b);
        return b;
    }

    private void refresh() {
        LinkService service = LinkService.instance;
        status.setText(service == null ? "Connection stopped." : service.status);
        paired.setText(service == null || service.macName.isEmpty() ? "No Mac paired" : "Mac: " + service.macName);
        code.setText(service == null ? "" : service.code);
        confirm.setVisibility(service != null && !service.code.isEmpty() && !service.localConfirmed ? View.VISIBLE : View.GONE);
        hotspotStatus.setText(service == null ? "" : service.hotspotStatus);
    }

    private void ensureConnection(String action) {
        if (Build.VERSION.SDK_INT >= 31 && (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED || checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED)) {
            permissionAction = action;
            requestPermissions(new String[]{Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE}, 10);
            return;
        }
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 11);
        send(action, null);
    }

    private void send(String action, String challenge) {
        Intent i = new Intent(this, LinkService.class);
        if (action != null) i.setAction(action);
        if (challenge != null) i.putExtra("qr", challenge);
        try {
            startForegroundService(i);
        } catch (Exception e) {
            Toast.makeText(this, "Allow Nearby devices and turn on Bluetooth first.", Toast.LENGTH_LONG).show();
        }
    }

    @Override
    public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(request, permissions, results);
        if (request == 10) {
            if (results.length > 0 && Arrays.stream(results).allMatch(r -> r == PackageManager.PERMISSION_GRANTED)) {
                String action = permissionAction;
                permissionAction = null;
                ensureConnection(action);
            }
        } else if (request == 12 && results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED)
            startActivityForResult(new Intent(this, ScannerActivity.class), 20);
    }

    @Override
    protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == 20 && result == RESULT_OK && data != null) {
            qr.setText(data.getStringExtra("qr"));
            ensureConnection(null);
            main.postDelayed(() -> {
                send("qr", qr.getText().toString());
                qr.setText("");
            }, 300);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        LinkService.observers.add(observer);
        main.post(refreshLoop);
    }

    @Override
    protected void onPause() {
        LinkService.observers.remove(observer);
        main.removeCallbacks(refreshLoop);
        super.onPause();
    }
}
