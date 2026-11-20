package com.leon.app;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
public class ConversationBranchApiTest {
    @Test public void branchUsesSourceCoordinatesAndStableRetryIdWithUpgradeFeedback()throws Exception {
        var server=new ServerSocket(0,8,InetAddress.getByName("127.0.0.1"));server.setSoTimeout(5000);
        var worker=Executors.newSingleThreadExecutor();
        var served=worker.submit(()->{
            for(int i=0;i<3;i++)try(var socket=server.accept()) {
                socket.setSoTimeout(5000);var input=new BufferedInputStream(socket.getInputStream());
                assertEquals("POST /api/conversations/dm:user:agent/branches HTTP/1.1",line(input));
                String header;int length=0;boolean authenticated=false;
                while(!(header=line(input)).isEmpty()) {
                    if(header.equals("Authorization: Bearer chat_branch_test"))authenticated=true;
                    if(header.startsWith("Content-Length: "))length=Integer.parseInt(header.substring(16));
                }
                assertTrue(authenticated);
                var payload=new JSONObject(new String(input.readNBytes(length),StandardCharsets.UTF_8));
                assertEquals(3,payload.length());assertEquals(7,payload.getLong("messageId"));
                assertEquals("stable-request",payload.getString("requestId"));assertEquals("方案 B",payload.getString("name"));
                String response=i==2?"{}":"{\"id\":\"branch:result\",\"name\":\"方案 B\",\"kind\":\"direct\",\"agentId\":\"agent\",\"agentIds\":[\"agent\"]}";
                byte[] bytes=response.getBytes(StandardCharsets.UTF_8);var output=socket.getOutputStream();
                output.write(("HTTP/1.1 "+(i==2?"404 Not Found":"200 OK")+"\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: "+bytes.length+"\r\n\r\n").getBytes(StandardCharsets.US_ASCII));
                output.write(bytes);output.flush();
            }
            return true;
        });
        try {
            var api=new MessageApi("http://127.0.0.1:"+server.getLocalPort(),"chat_branch_test");
            for(int i=0;i<2;i++)assertEquals("branch:result",api.branch("dm:user:agent",7,"stable-request","方案 B").id);
            try {api.branch("dm:user:agent",7,"stable-request","方案 B");fail("old server accepted branch");}
            catch(IOException expected){assertTrue(expected.getMessage().contains("升级"));}
            assertTrue(served.get(8,TimeUnit.SECONDS));
            for(String invalid:new String[]{"../admin","room/path","room?query"}) {
                try {api.branch(invalid,7,"stable-request","方案 B");fail("unsafe path accepted");}
                catch(IOException expected){assertTrue(expected.getMessage().contains("标识"));}
            }
        } finally {server.close();worker.shutdownNow();}
    }
    private static String line(InputStream input)throws IOException {
        var bytes=new ByteArrayOutputStream();for(int b;(b=input.read())!=-1;){if(b=='\n')break;if(b!='\r')bytes.write(b);}
        return bytes.toString(StandardCharsets.US_ASCII.name());
    }
}
