package com.leon.app;

import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.UUID;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
public class ChatDocumentTest {
    @Test public void pendingDocumentBytesAreDurableAndAccountScoped()throws Exception{
        File root=Files.createTempDirectory("leon-documents").toFile();String first="outbox."+"a".repeat(64),other="outbox."+"b".repeat(64);byte[] data="月份,营收\n十一月,123".getBytes(StandardCharsets.UTF_8);
        var doc=new ChatDocument("销售.csv",data);doc.save(root,first);
        assertArrayEquals(data,ChatDocument.local(root,first,doc.id));assertEquals(doc.name,new ChatDocument(doc.json()).name);
        try{ChatDocument.local(root,other,doc.id);fail("cross-account document found");}catch(FileNotFoundException expected){}
        ChatDocument.remove(root,first,doc.id);assertFalse(ChatDocument.file(root,first,doc.id).exists());
        try{ChatDocument.file(root,"../escape",UUID.randomUUID().toString());fail("unsafe scope accepted");}catch(IOException expected){}
    }
    @Test public void documentReadsEnforceByteLimit()throws Exception{
        assertArrayEquals(new byte[]{1,2},ChatDocument.bounded(new ByteArrayInputStream(new byte[]{1,2})));
        try{ChatDocument.bounded(new ByteArrayInputStream(new byte[ChatDocument.MAX_BYTES+1]));fail("oversize document accepted");}catch(IOException expected){}
    }
}
