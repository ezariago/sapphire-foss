package dev.sapphire.companion;

import org.json.*;

import java.time.Instant;
import java.util.UUID;

/**
 * Keep field types compatible with the Mac's Codable PhoneEnvelope.
 */
final class LinkEnvelope {
    static JSONObject encode(String type, JSONObject payload) throws JSONException {
        JSONObject envelope = new JSONObject();
        envelope.put("v", 1);
        envelope.put("id", UUID.randomUUID().toString());
        envelope.put("type", type);
        envelope.put("ts", Instant.now().toString());
        envelope.put("counter", 0);
        envelope.put("payload", payload);
        return envelope;
    }
}
