package dev.sapphire.companion;

import java.io.ByteArrayOutputStream;
import java.util.*;

final class GattFrames {
    private static final class Partial {
        final long started;
        final ByteArrayOutputStream data = new ByteArrayOutputStream();

        Partial(long now) {
            started = now;
        }
    }

    private final Map<Integer, Partial> partials = new HashMap<>();

    byte[] accept(byte[] chunk, long now) throws Exception {
        partials.entrySet().removeIf(e -> now - e.getValue().started > 15000);
        if (chunk.length < 3 || (chunk[0] & ~3) != 0)
            throw new IllegalArgumentException("Invalid fragment");
        int id = (chunk[1] & 255) | ((chunk[2] & 255) << 8);
        if ((chunk[0] & 1) != 0) {
            if (partials.size() >= 16) throw new IllegalArgumentException("Too many fragments");
            partials.put(id, new Partial(now));
        }
        Partial p = partials.get(id);
        if (p == null) throw new IllegalArgumentException("Orphan fragment");
        if (p.data.size() + chunk.length - 3 > 16384) {
            partials.remove(id);
            throw new IllegalArgumentException("Message too large");
        }
        p.data.write(chunk, 3, chunk.length - 3);
        if ((chunk[0] & 2) != 0) {
            partials.remove(id);
            return p.data.toByteArray();
        }
        return null;
    }

    static List<byte[]> split(byte[] data, int id, int maximum) {
        if (data.length > 16384 || maximum < 4)
            throw new IllegalArgumentException("Invalid message size");
        List<byte[]> out = new ArrayList<>();
        int capacity = maximum - 3;
        for (int offset = 0; offset < data.length; offset += capacity) {
            int end = Math.min(data.length, offset + capacity);
            byte[] b = new byte[3 + end - offset];
            b[0] = (byte) ((offset == 0 ? 1 : 0) | (end == data.length ? 2 : 0));
            b[1] = (byte) id;
            b[2] = (byte) (id >> 8);
            System.arraycopy(data, offset, b, 3, end - offset);
            out.add(b);
        }
        return out;
    }
}
