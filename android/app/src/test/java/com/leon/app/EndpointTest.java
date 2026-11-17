package com.leon.app;

import org.junit.Test;
import static org.junit.Assert.*;

public class EndpointTest {
    @Test public void acceptsHttpsAndExplicitDevelopmentHosts() {
        assertEquals("https://example.com", Endpoint.normalize(" https://example.com/ "));
        assertEquals("https://121.40.254.112", Endpoint.normalize("https://121.40.254.112"));
        assertEquals("http://10.0.2.2:8080", Endpoint.normalize("http://10.0.2.2:8080"));
    }
    @Test public void rejectsCredentialLeaksAndInsecureRemoteServers() {
        for (String value : new String[]{"http://example.com", "https://token@example.com", "https://example.com?token=x",
                "https://example.com/api", "https://example.com#x", "ftp://example.com", "garbage", "https://example.com:99999"}) {
            assertThrows(value, IllegalArgumentException.class, () -> Endpoint.normalize(value));
        }
    }
}
