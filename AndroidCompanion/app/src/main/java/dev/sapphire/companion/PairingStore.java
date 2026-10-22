package dev.sapphire.companion;

import android.content.Context;
import android.security.keystore.*;
import android.util.Base64;

import org.json.JSONObject;

import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;

import java.security.KeyStore;
import java.util.Arrays;

/**
 * Only encrypted bytes go into private preferences. Auto Backup is disabled.
 */
final class PairingStore {
    private final Context context;
    private static final String ALIAS = "sapphire-companion-pairing-v1";

    PairingStore(Context context) {
        this.context = context;
    }

    private SecretKey key() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (!ks.containsAlias(ALIAS)) {
            KeyGenerator g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            g.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            g.generateKey();
        }
        return ((KeyStore.SecretKeyEntry) ks.getEntry(ALIAS, null)).getSecretKey();
    }

    void save(JSONObject record) throws Exception {
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.ENCRYPT_MODE, key());
        c.updateAAD(LinkCrypto.utf8(ALIAS));
        byte[] blob = LinkCrypto.concat(c.getIV(), c.doFinal(LinkCrypto.utf8(record.toString())));
        if (!context.getSharedPreferences("pairing", 0).edit().putString("record", Base64.encodeToString(blob, Base64.NO_WRAP)).commit())
            throw new java.io.IOException("Pairing was not saved");
    }

    JSONObject load() throws Exception {
        String value = context.getSharedPreferences("pairing", 0).getString("record", null);
        if (value == null) return null;
        byte[] blob = Base64.decode(value, Base64.NO_WRAP);
        if (blob.length < 29)
            throw new java.security.GeneralSecurityException("Invalid pairing record");
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Arrays.copyOf(blob, 12)));
        c.updateAAD(LinkCrypto.utf8(ALIAS));
        return new JSONObject(new String(c.doFinal(Arrays.copyOfRange(blob, 12, blob.length)), java.nio.charset.StandardCharsets.UTF_8));
    }

    void clear() {
        context.getSharedPreferences("pairing", 0).edit().remove("record").apply();
    }
}
