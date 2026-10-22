package dev.sapphire.companion;

import android.content.*;
import android.net.*;
import android.os.*;
import android.telephony.*;
import org.json.*;

/** Public, permission-free radio summaries; never reads phone or SIM identifiers. */
final class PhoneStatus {
    static JSONObject read(Context context) {
        JSONObject result = new JSONObject();
        try {
            Intent battery = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            if (battery != null) {
                int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
                if (level >= 0 && scale > 0) result.put("batteryPercent", Math.min(100, level * 100 / scale));
                int state = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
                result.put("charging", state == BatteryManager.BATTERY_STATUS_CHARGING || state == BatteryManager.BATTERY_STATUS_FULL);
            }
            result.put("deviceName", Build.MODEL);
            result.put("hotspotMode", "internet");
            result.put("hotspotStopSupported", true);
        } catch (Exception ignored) { }
        try {
            TelephonyManager radio = context.getSystemService(TelephonyManager.class);
            int subscription = SubscriptionManager.getDefaultDataSubscriptionId();
            if (radio != null) {
                if (SubscriptionManager.isValidSubscriptionId(subscription)) radio = radio.createForSubscriptionId(subscription);
                String carrier = radio.getNetworkOperatorName();
                if (carrier != null && !carrier.trim().isEmpty()) result.put("carrier", carrier.trim());
                SignalStrength signal = radio.getSignalStrength();
                // Android's cached modem level is 0...4; null means unavailable.
                if (signal != null) result.put("signalLevel", signal.getLevel());
            }
        } catch (Exception ignored) { /* No radio, no SIM, or OEM restriction: omit unknown values. */ }
        try {
            ConnectivityManager connectivity = context.getSystemService(ConnectivityManager.class);
            Network network = connectivity.getActiveNetwork();
            NetworkCapabilities capabilities = connectivity.getNetworkCapabilities(network);
            if (capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) result.put("network", "wifi");
            else if (capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) result.put("network", "cellular");
            else if (network == null) result.put("network", "none");
        } catch (Exception ignored) { }
        return result;
    }
}
