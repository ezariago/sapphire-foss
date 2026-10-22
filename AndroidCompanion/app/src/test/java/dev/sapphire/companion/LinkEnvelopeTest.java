package dev.sapphire.companion;

import org.junit.Test;

import static org.junit.Assert.*;

import org.json.JSONObject;

public class LinkEnvelopeTest {
    @Test
    public void matchesMacCodableFieldTypes() throws Exception {
        JSONObject payload = new JSONObject().put("nonce", "fixture");
        JSONObject message = LinkEnvelope.encode("pair.hello", payload);
        assertEquals(1, message.getInt("v"));
        assertNotNull(java.util.UUID.fromString(message.getString("id")));
        assertEquals("pair.hello", message.getString("type"));
        assertTrue(message.get("ts") instanceof String);
        assertNotNull(java.time.Instant.parse(message.getString("ts")));
        assertEquals(0, message.getLong("counter"));
        assertEquals("fixture", message.getJSONObject("payload").getString("nonce"));
    }
}
