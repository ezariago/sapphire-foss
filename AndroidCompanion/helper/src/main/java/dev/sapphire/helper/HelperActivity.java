package dev.sapphire.helper;

import android.app.*;
import android.os.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.provider.Settings;
import android.widget.*;

import rikka.shizuku.Shizuku;

public final class HelperActivity extends Activity {
    private TextView status;
    private final Shizuku.OnBinderReceivedListener received = () -> runOnUiThread(this::refresh);
    private final Shizuku.OnBinderDeadListener dead = () -> runOnUiThread(this::refresh);
    private final Shizuku.OnRequestPermissionResultListener permission = (request, result) -> runOnUiThread(this::refresh);

    @Override
    public void onCreate(Bundle saved) {
        super.onCreate(saved);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(1);
        content.setPadding(32, 72, 32, 32);
        TextView title = new TextView(this);
        title.setText("Hotspot Helper");
        title.setTextSize(30);
        content.addView(title);
        TextView explanation = new TextView(this);
        explanation.setText("Lets your paired Mac turn Android’s mobile hotspot on and off. Only your matching Sapphire Companion app can call this helper.\n\nOn Android 16, Shizuku must be installed, running and authorized. Older SDK targeting alone cannot enable tethering on current Android. Carrier rules still apply.");
        explanation.setPadding(0, 24, 0, 24);
        content.addView(explanation);
        status = new TextView(this);
        content.addView(status);
        Button authorize = new Button(this);
        authorize.setText("Authorize hotspot control");
        authorize.setOnClickListener(v -> {
            try {
                if (!Shizuku.pingBinder())
                    new AlertDialog.Builder(this).setMessage("Start Shizuku first, then return here. Shizuku may need to be restarted after reboot.").setPositiveButton("OK", null).show();
                else Shizuku.requestPermission(100);
            } catch (Exception e) {
                refresh();
            }
        });
        content.addView(authorize);
        Button open = new Button(this);
        open.setText("Open Shizuku");
        open.setOnClickListener(v -> {
            Intent i = getPackageManager().getLaunchIntentForPackage("moe.shizuku.privileged.api");
            if (i != null) startActivity(i);
            else
                new AlertDialog.Builder(this).setMessage("Install Shizuku from shizuku.rikka.app, start it using its setup instructions, then return here.").setPositiveButton("OK", null).show();
        });
        content.addView(open);
        Button settings = new Button(this);
        settings.setText("Open Android hotspot settings");
        settings.setOnClickListener(v -> {
            try {
                startActivity(new Intent("android.settings.TETHER_SETTINGS"));
            } catch (Exception e) {
                startActivity(new Intent(Settings.ACTION_WIRELESS_SETTINGS));
            }
        });
        content.addView(settings);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        setContentView(scroll);
        Shizuku.addBinderReceivedListenerSticky(received);
        Shizuku.addBinderDeadListener(dead);
        Shizuku.addRequestPermissionResultListener(permission);
        refresh();
    }

    private void refresh() {
        boolean running = Shizuku.pingBinder();
        boolean allowed = running && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED;
        status.setText(allowed ? "Ready — hotspot control authorized." : running ? "Shizuku is running. Authorization is needed." : "Shizuku is not running.");
    }

    @Override
    public void onDestroy() {
        Shizuku.removeBinderReceivedListener(received);
        Shizuku.removeBinderDeadListener(dead);
        Shizuku.removeRequestPermissionResultListener(permission);
        super.onDestroy();
    }
}
