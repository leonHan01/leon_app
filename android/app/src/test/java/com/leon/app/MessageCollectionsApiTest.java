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
public class MessageCollectionsApiTest {
    @Test public void quoteCapabilityPayloadAndPrivateFavoritesUseAuthenticatedEndpoints()throws Exception{
        var server=new ServerSocket(0,8,InetAddress.getByName("127.0.0.1"));server.setSoTimeout(5000);var worker=Executors.newSingleThreadExecutor();
        String message="{\"id\":9,\"clientMessageId\":\"client\",\"deviceId\":\"device\",\"sender\":\"Alice\",\"platform\":\"android\",\"text\":\"reply\",\"createdAt\":1000,\"conversationId\":\"thread:one\",\"quote\":{\"id\":7,\"sender\":\"Bob\",\"text\":\"source\",\"images\":[]}}";
        String favorite="{\"id\":12,\"message\":"+message+",\"conversationName\":\"测试\",\"savedAt\":1000}";
        var served=worker.submit(()->{
            for(int i=0;i<7;i++)try(var socket=server.accept()){
                socket.setSoTimeout(5000);var input=new BufferedInputStream(socket.getInputStream());String request=line(input),header;int length=0;boolean auth=false;
                while(!(header=line(input)).isEmpty()){
                    if(header.equals("Authorization: Bearer chat_collection_test"))auth=true;
                    if(header.startsWith("Content-Length: "))length=Integer.parseInt(header.substring(16));
                }
                assertTrue(auth);byte[] body=input.readNBytes(length);String response="{}";
                switch(i){
                    case 0 -> {assertEquals("GET /api/device-messages/features HTTP/1.1",request);response="{\"quotes\":true,\"favorites\":true}";}
                    case 1 -> {assertEquals("POST /api/device-messages HTTP/1.1",request);var payload=new JSONObject(new String(body,StandardCharsets.UTF_8));assertEquals(7,payload.getLong("quoteMessageId"));assertFalse(payload.has("quote"));response=message;}
                    case 2 -> {assertEquals("POST /api/device-messages/9/favorite HTTP/1.1",request);response=favorite;}
                    case 3 -> {assertEquals("GET /api/device-messages/favorites?q=%E4%B8%AD%E6%96%87+%25_%26%2B&before=20 HTTP/1.1",request);response="{\"results\":["+favorite+"],\"hasMore\":false,\"nextBefore\":null}";}
                    case 4 -> {assertEquals("POST /api/device-messages/favorites/12/remove HTTP/1.1",request);response="{\"removed\":true}";}
                    case 5 -> {assertEquals("GET /api/device-messages/favorites/12/images/11111111-1111-4111-8111-111111111111 HTTP/1.1",request);response="image-bytes";}
                    case 6 -> assertEquals("GET /api/device-messages/features HTTP/1.1",request);
                }
                byte[] bytes=response.getBytes(StandardCharsets.UTF_8);var output=socket.getOutputStream();output.write(("HTTP/1.1 "+(i==6?"404 Not Found":"200 OK")+"\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: "+bytes.length+"\r\n\r\n").getBytes(StandardCharsets.US_ASCII));output.write(bytes);output.flush();
            }return true;
        });
        try{
            var api=new MessageApi("http://127.0.0.1:"+server.getLocalPort(),"chat_collection_test");
            var body=new JSONObject().put("clientMessageId","client").put("quoteMessageId",7).put("quote",new JSONObject().put("text","untrusted"));
            assertEquals(7,api.send(body).quote.id);assertEquals(12,api.addFavorite(9).id);
            assertEquals("source",api.favorites("中文 %_&+",20L).results.get(0).message.quote.text);api.removeFavorite(12);
            assertArrayEquals("image-bytes".getBytes(StandardCharsets.UTF_8),api.favoriteImage(12,"11111111-1111-4111-8111-111111111111"));
            try{api.send(body);fail("old server accepted quoted message");}catch(IOException expected){assertTrue(expected.getMessage().contains("升级"));}
            assertTrue(served.get(8,TimeUnit.SECONDS));
        }finally{server.close();worker.shutdownNow();}
    }
    private static String line(InputStream input)throws IOException{
        var bytes=new ByteArrayOutputStream();for(int b;(b=input.read())!=-1;){if(b=='\n')break;if(b!='\r')bytes.write(b);}return bytes.toString(StandardCharsets.US_ASCII.name());
    }
}
