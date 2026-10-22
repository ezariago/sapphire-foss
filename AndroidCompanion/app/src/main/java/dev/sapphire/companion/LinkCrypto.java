package dev.sapphire.companion;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.interfaces.ECPublicKey;
import java.security.spec.*;
import java.util.*;

import javax.crypto.*;
import javax.crypto.spec.*;

/**
 * Wire-compatible with the Mac's PhoneWire.swift; no Android dependencies.
 */
public final class LinkCrypto {
    public static byte[] random(int length) {
        byte[] out = new byte[length];
        new SecureRandom().nextBytes(out);
        return out;
    }

    public static byte[] concat(byte[]... parts) {
        int count = 0;
        for (byte[] p : parts) count += p.length;
        ByteBuffer out = ByteBuffer.allocate(count);
        for (byte[] p : parts) out.put(p);
        return out.array();
    }

    public static byte[] utf8(String s) {
        return s.getBytes(StandardCharsets.UTF_8);
    }

    public static byte[] hash(byte[] b) throws Exception {
        return MessageDigest.getInstance("SHA-256").digest(b);
    }

    public static KeyPair keyPair() throws Exception {
        KeyPairGenerator g = KeyPairGenerator.getInstance("EC");
        g.initialize(new ECGenParameterSpec("secp256r1"));
        return g.generateKeyPair();
    }

    private static byte[] coordinate(java.math.BigInteger i) {
        byte[] value = i.toByteArray(), out = new byte[32];
        System.arraycopy(value, Math.max(0, value.length - 32), out, Math.max(0, 32 - value.length), Math.min(32, value.length));
        return out;
    }

    public static byte[] publicPoint(PublicKey p) {
        ECPublicKey ec = (ECPublicKey) p;
        return concat(new byte[]{4}, coordinate(ec.getW().getAffineX()), coordinate(ec.getW().getAffineY()));
    }

    public static byte[] shared(PrivateKey key, byte[] point) throws Exception {
        if (point.length != 65 || point[0] != 4)
            throw new GeneralSecurityException("Invalid public key");
        AlgorithmParameters params = AlgorithmParameters.getInstance("EC");
        params.init(new ECGenParameterSpec("secp256r1"));
        PublicKey publicKey = KeyFactory.getInstance("EC").generatePublic(new ECPublicKeySpec(new ECPoint(
                new java.math.BigInteger(1, Arrays.copyOfRange(point, 1, 33)), new java.math.BigInteger(1, Arrays.copyOfRange(point, 33, 65))), params.getParameterSpec(ECParameterSpec.class)));
        KeyAgreement agreement = KeyAgreement.getInstance("ECDH");
        agreement.init(key);
        agreement.doPhase(publicKey, true);
        return agreement.generateSecret();
    }

    public static byte[] hkdf(byte[] key, byte[] salt, String info, int length) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(salt, "HmacSHA256"));
        byte[] prk = mac.doFinal(key);
        mac.init(new SecretKeySpec(prk, "HmacSHA256"));
        byte[] block = mac.doFinal(concat(utf8(info), new byte[]{1}));
        if (length > 32) throw new IllegalArgumentException("HKDF output too long");
        return Arrays.copyOf(block, length);
    }

    public static String sas(byte[] shared, byte[] salt) throws Exception {
        long value = Integer.toUnsignedLong(ByteBuffer.wrap(hkdf(shared, salt, "sapphire-continuity-sas", 8)).getInt());
        return String.format(Locale.ROOT, "%06d", value % 1_000_000);
    }

    public static final class Session {
        private final byte[] sendKey, receiveKey;
        private long outgoing, highestIncoming;
        private final Set<Long> seen = new HashSet<>();

        public Session(byte[] linkKey, byte[] macNonce, byte[] phoneNonce, boolean phone) throws Exception {
            if (linkKey.length != 32 || macNonce.length != 32 || phoneNonce.length != 32)
                throw new GeneralSecurityException("Invalid nonce");
            byte[] salt = concat(macNonce, phoneNonce);
            byte[] m = hkdf(linkKey, salt, "sapphire.ble.mac-to-phone.v1", 32), p = hkdf(linkKey, salt, "sapphire.ble.phone-to-mac.v1", 32);
            sendKey = phone ? p : m;
            receiveKey = phone ? m : p;
        }

        public byte[] seal(byte[] plain) throws Exception {
            if (plain.length > 16356 || outgoing == Long.MAX_VALUE)
                throw new GeneralSecurityException("Frame too large");
            long counter = ++outgoing;
            byte[] header = concat(utf8("SBE1"), ByteBuffer.allocate(8).putLong(counter).array());
            Cipher c = cipher(Cipher.ENCRYPT_MODE, sendKey, header, counter);
            return concat(header, c.doFinal(plain));
        }

        public byte[] open(byte[] frame) throws Exception {
            if (frame.length < 28 || frame.length > 16384 || !Arrays.equals(Arrays.copyOf(frame, 4), utf8("SBE1")))
                throw new GeneralSecurityException("Invalid frame");
            long counter = ByteBuffer.wrap(frame, 4, 8).getLong();
            if (counter <= 0 || seen.contains(counter) || (counter < highestIncoming && highestIncoming - counter > 256))
                throw new GeneralSecurityException("Replay rejected");
            byte[] plain = cipher(Cipher.DECRYPT_MODE, receiveKey, Arrays.copyOf(frame, 12), counter).doFinal(Arrays.copyOfRange(frame, 12, frame.length));
            highestIncoming = Math.max(highestIncoming, counter);
            seen.add(counter);
            seen.removeIf(i -> highestIncoming - i > 256);
            return plain;
        }

        private static Cipher cipher(int mode, byte[] key, byte[] header, long counter) throws Exception {
            Cipher c = Cipher.getInstance("ChaCha20-Poly1305");
            c.init(mode, new SecretKeySpec(key, "ChaCha20"), new IvParameterSpec(ByteBuffer.allocate(12).putInt(0).putLong(counter).array()));
            c.updateAAD(header);
            return c;
        }
    }
}
