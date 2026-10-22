// Independent Java/JCA fixture for the companion's published-on-wire algorithms.
// Fixed test keys only. No device credentials or proprietary code are included.
import java.security.*;
import java.security.spec.*;
import javax.crypto.*;
import javax.crypto.spec.*;
import java.math.BigInteger;
import java.util.*;
import java.nio.charset.StandardCharsets;

class AndroidCryptoFixture {
    static byte[] sequence(int start, int length) {
        byte[] result = new byte[length];
        for (int i = 0; i < length; i++) result[i] = (byte)(start + i);
        return result;
    }
    static byte[] concat(byte[] a, byte[] b) {
        byte[] result = Arrays.copyOf(a, a.length + b.length);
        System.arraycopy(b, 0, result, a.length, b.length);
        return result;
    }
    static byte[] hkdf(byte[] ikm, byte[] salt, String info, int length) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(salt, "HmacSHA256"));
        byte[] prk = mac.doFinal(ikm);
        mac.init(new SecretKeySpec(prk, "HmacSHA256"));
        byte[] output = new byte[length], previous = new byte[0];
        int offset = 0;
        for (int i = 1; offset < length; i++) {
            mac.update(previous);
            mac.update(info.getBytes(StandardCharsets.UTF_8));
            mac.update((byte)i);
            previous = mac.doFinal();
            int count = Math.min(previous.length, length - offset);
            System.arraycopy(previous, 0, output, offset, count);
            offset += count;
        }
        return output;
    }
    public static void main(String[] args) throws Exception {
        AlgorithmParameters parameters = AlgorithmParameters.getInstance("EC");
        parameters.init(new ECGenParameterSpec("secp256r1"));
        ECParameterSpec curve = parameters.getParameterSpec(ECParameterSpec.class);
        KeyFactory factory = KeyFactory.getInstance("EC");
        PrivateKey macPrivate = factory.generatePrivate(new ECPrivateKeySpec(BigInteger.ONE, curve));
        ECPoint phonePoint = new ECPoint(
            new BigInteger("7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978", 16),
            new BigInteger("07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1", 16));
        PublicKey phonePublic = factory.generatePublic(new ECPublicKeySpec(phonePoint, curve));
        KeyAgreement agreement = KeyAgreement.getInstance("ECDH");
        agreement.init(macPrivate); agreement.doPhase(phonePublic, true);
        byte[] salt = concat(sequence(0, 16), sequence(16, 16));
        byte[] shared = agreement.generateSecret();
        byte[] link = hkdf(shared, salt, "sapphire-continuity-link", 32);
        byte[] sas = hkdf(shared, salt, "sapphire-continuity-sas", 8);
        long code = 0;
        for (int i = 0; i < 4; i++) code = (code << 8) | (sas[i] & 255);
        byte[] m2p = hkdf(link, concat(sequence(0, 32), sequence(32, 32)), "sapphire.ble.mac-to-phone.v1", 32);
        byte[] nonce = new byte[12]; nonce[11] = 1;
        byte[] header = new byte[]{83, 66, 69, 49, 0, 0, 0, 0, 0, 0, 0, 1};
        Cipher cipher = Cipher.getInstance("ChaCha20-Poly1305");
        cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(m2p, "ChaCha20"), new IvParameterSpec(nonce));
        cipher.updateAAD(header);
        byte[] frame = concat(header, cipher.doFinal("{\"type\":\"status.request\"}".getBytes(StandardCharsets.UTF_8)));
        Base64.Encoder b64 = Base64.getEncoder();
        System.out.println("{\"linkKey\":\"" + b64.encodeToString(link) + "\",\"sas\":\"" + String.format("%06d", code % 1000000) + "\",\"frame\":\"" + b64.encodeToString(frame) + "\"}");
    }
}
