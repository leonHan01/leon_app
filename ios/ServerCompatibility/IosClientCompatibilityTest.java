package com.leon.workflow.messaging;

import com.example.helloservice.HelloServiceApplication;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(classes=HelloServiceApplication.class,properties={
    "spring.datasource.url=jdbc:h2:mem:ios-client-compatibility;DB_CLOSE_DELAY=-1",
    "spring.jpa.hibernate.ddl-auto=create-drop", "leon.workflows.scheduling-enabled=false",
    "leon.agents.dispatch-enabled=false"})
class IosClientCompatibilityTest {
    @Autowired DeviceMessageStore store;
    @Autowired ChatBackupService backups;
    @Test void iosMessagesRetryAndBackupRoundTripKeepTheirPlatform() {
        var input=new DeviceMessageStore.Send(UUID.randomUUID().toString(),UUID.randomUUID().toString(),"iPhone","ios","iOS 兼容测试");
        var saved=store.send(input);
        assertEquals("ios",saved.platform());
        assertEquals(saved.id(),store.send(input).id());
        var restored=backups.restore(UUID.randomUUID().toString(),null,backups.export("shared"));
        assertTrue(store.page(restored.id(),null,null,100).messages().stream().anyMatch(m->m.platform().equals("ios")&&m.text().equals("iOS 兼容测试")));
    }
    @Test void iosPresenceIsAcceptedWhileBrowserPresenceIsRejected() {
        var presence=new DevicePresenceService();
        var id=UUID.randomUUID().toString();
        presence.heartbeat(new DevicePresenceService.Heartbeat(id,"iPhone","ios"));
        assertEquals(1,presence.online().get("onlineCount"));
        assertThrows(Exception.class,()->presence.heartbeat(new DevicePresenceService.Heartbeat(UUID.randomUUID().toString(),"Browser","web")));
    }
}
