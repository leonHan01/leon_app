package com.leon.app;

import java.net.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
public class ChatToolsApiTest {
    @Test public void commandsAndLargeBackupsUseAuthenticatedConversationEndpoints()throws Exception{
        var server=new ServerSocket(0,5,InetAddress.getByName("127.0.0.1"));server.setSoTimeout(10000);
        var worker=Executors.newSingleThreadExecutor();byte[] backup=new byte[5_100_000];java.util.Arrays.fill(backup,(byte)'z');
        var served=worker.submit(()->{
            for(int i=0;i<6;i++)try(var socket=server.accept()){
                socket.setSoTimeout(10000);var input=new BufferedInputStream(socket.getInputStream());
                String request=line(input);String header;int length=0;boolean authenticated=false;
                while(!(header=line(input)).isEmpty()){
                    if(header.equals("Authorization: Bearer chat-tools-test-token"))authenticated=true;
                    if(header.startsWith("Content-Length: "))length=Integer.parseInt(header.substring(16));
                }
                assertTrue(authenticated);byte[] body=ChatTools.readLimited(input,length);assertEquals(length,body.length);
                String response="{}";
                switch(i){
                    case 0 -> {assertEquals("GET /api/conversations/context?conversationId=direct%3Asol HTTP/1.1",request);response="{\"recentRounds\":10}";}
                    case 1 -> {assertTrue(request.startsWith("GET /api/conversations/context/clear-preview?"));response="{\"messageCount\":12,\"historyRevision\":2}";}
                    case 2 -> {assertEquals("POST /api/conversations/context/compact HTTP/1.1",request);assertEquals("direct:sol",new JSONObject(new String(body,StandardCharsets.UTF_8)).getString("conversationId"));}
                    case 3 -> {assertTrue(request.startsWith("POST /api/conversations/direct/sol/threads "));response=room();}
                    case 4 -> assertTrue(request.startsWith("GET /api/conversations/backups?"));
                    case 5 -> {assertTrue(request.startsWith("POST /api/conversations/backups?requestId=request-one&agentId=sol "));assertArrayEquals(backup,body);response=room();}
                }
                byte[] bytes=i==4?backup:response.getBytes(StandardCharsets.UTF_8);
                var out=socket.getOutputStream();out.write(("HTTP/1.1 200 OK\r\nContent-Type: "+(i==4?"application/zip":"application/json")+"\r\nConnection: close\r\nContent-Length: "+bytes.length+"\r\n\r\n").getBytes(StandardCharsets.US_ASCII));out.write(bytes);out.flush();
            }return null;
        });
        try{
            var api=new MessageApi("http://127.0.0.1:"+server.getLocalPort(),"chat-tools-test-token");
            assertEquals(10,api.context("direct:sol").getInt("recentRounds"));assertEquals(12,api.clearPreview("direct:sol").getInt("messageCount"));
            api.contextAction("compact",new JSONObject().put("conversationId","direct:sol"));
            assertEquals("独立对话",api.newThread("sol","new-thread","周末").name);
            assertArrayEquals(backup,api.backup("direct:sol"));assertEquals("thread:one",api.restoreBackup(backup,"request-one","sol").id);
            served.get(10,TimeUnit.SECONDS);
        }finally{server.close();worker.shutdownNow();}
    }
    private static String room(){return "{\"id\":\"thread:one\",\"name\":\"独立对话\",\"kind\":\"direct\",\"agentId\":\"sol\",\"agentIds\":[\"sol\"]}";}
    private static String line(InputStream input)throws IOException{
        var bytes=new ByteArrayOutputStream();for(int b;(b=input.read())!=-1;){if(b=='\n')break;if(b!='\r')bytes.write(b);}return bytes.toString(StandardCharsets.US_ASCII.name());
    }
}
