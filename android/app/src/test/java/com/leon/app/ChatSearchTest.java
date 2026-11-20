package com.leon.app;

import android.os.Looper;
import android.text.Spanned;
import android.text.style.ForegroundColorSpan;
import android.widget.EditText;
import android.widget.TextView;
import org.json.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import java.net.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.*;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
public class ChatSearchTest {
    @Test public void excerptsFindDistantLiteralMatchesAndPreserveSurrogates(){
        String body="😀前文".repeat(100)+"a.b%_"+"后文".repeat(100);
        String excerpt=ChatSearch.excerpt(body,"a.b%_");assertTrue(excerpt.contains("a.b%_"));assertTrue(excerpt.startsWith("…"));
        assertFalse(excerpt.contains("\uFFFD"));
        Spanned value=(Spanned)ChatSearch.highlight("a.b axb A.B","a.b");
        assertEquals(2,value.getSpans(0,value.length(),ForegroundColorSpan.class).length);
    }
    @Test public void searchAndContextUseAuthenticatedLiteralQueriesAndStableCursors()throws Exception{
        List<String> paths=new CopyOnWriteArrayList<>();
        try(var fixture=new Fixture(path->{paths.add(path);return path.startsWith("/api/device-messages/context")?context(1):"{\"results\":[],\"hasMore\":true,\"nextBefore\":42}";})){
            var api=new MessageApi(fixture.url(),"chat_search_test");
            assertEquals(Long.valueOf(42),api.search("中文 %_&+?#",null,null).nextBefore);
            api.search("literal","thread:one",42L);
            assertEquals(1,api.searchContext("thread:one",55,"before").historyRevision);
            assertEquals("/api/device-messages/search?q=%E4%B8%AD%E6%96%87+%25_%26%2B%3F%23",paths.get(0));
            assertTrue(paths.get(1).endsWith("&conversationId=thread%3Aone&before=42"));
            assertEquals("/api/device-messages/context?conversationId=thread%3Aone&messageId=55&direction=before",paths.get(2));
            assertEquals(3,fixture.authorized.get());
        }
    }
    @Test public void clearingSearchRejectsALateResponseAndPreservesChatDraft()throws Exception{
        var release=new CountDownLatch(1);var arrived=new CountDownLatch(1);
        try(var fixture=new Fixture(path->{arrived.countDown();release.await(4,TimeUnit.SECONDS);return page(99,"旧结果");})){
            var controller=Robolectric.buildActivity(MainActivity.class).setup();var activity=controller.get();ChatSearch search=null;
            try{
                var field=MainActivity.class.getDeclaredField("session");field.setAccessible(true);var session=(ChatSession)field.get(activity);session.stop();session.draft="未发送草稿";
                field=ChatSession.class.getDeclaredField("api");field.setAccessible(true);field.set(session,new MessageApi(fixture.url(),"chat_search_test"));
                search=new ChatSearch(activity,session,id->fail("search must not navigate on its own"));search.show("shared","当前聊天");
                var dialog=org.robolectric.shadows.ShadowDialog.getLatestDialog();var input=(EditText)dialog.findViewById(R.id.chat_search_input);
                input.setText("旧词");Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400));
                assertTrue(arrived.await(2,TimeUnit.SECONDS));input.setText("");release.countDown();
                drain(()->fixture.completed.get()>0);Shadows.shadowOf(Looper.getMainLooper()).idle();
                assertNull(dialog.getWindow().getDecorView().findViewWithTag("search-result:99"));
                assertEquals("未发送草稿",session.draft);search.dismiss();assertEquals("未发送草稿",session.draft);
                search.show(null,"全部聊天记录");var reopened=org.robolectric.shadows.ShadowDialog.getLatestDialog();
                ((EditText)reopened.findViewById(R.id.chat_search_input)).setText("新搜索");
                Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400));
                drain(()->reopened.getWindow().getDecorView().findViewWithTag("search-result:99")!=null);

            }finally{release.countDown();if(search!=null)search.close();controller.pause().stop().destroy();}
        }
    }
    @Test public void resultOpensOriginalContextAndBackKeepsTheSearch()throws Exception{
        try(var fixture=new Fixture(path->path.startsWith("/api/device-messages/context")?context(2):page(7,"命中的消息"))){
            var controller=Robolectric.buildActivity(MainActivity.class).setup();var activity=controller.get();ChatSearch search=null;
            try{
                var field=MainActivity.class.getDeclaredField("session");field.setAccessible(true);var session=(ChatSession)field.get(activity);session.stop();
                field=ChatSession.class.getDeclaredField("api");field.setAccessible(true);field.set(session,new MessageApi(fixture.url(),"chat_search_test"));
                search=new ChatSearch(activity,session,id->{});search.show(null,"全部聊天记录");
                var dialog=org.robolectric.shadows.ShadowDialog.getLatestDialog();var input=(EditText)dialog.findViewById(R.id.chat_search_input);
                input.setText("命中");Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400));
                drain(()->dialog.getWindow().getDecorView().findViewWithTag("search-result:7")!=null);
                dialog.getWindow().getDecorView().findViewWithTag("search-result:7").performClick();
                drain(()->allText(dialog.getWindow().getDecorView()).contains("原始上下文"));
                assertTrue(allText(dialog.getWindow().getDecorView()).contains("进入会话"));
                assertTrue(allText(dialog.getWindow().getDecorView()).contains("原始上下文"));
                var method=ChatSearch.class.getDeclaredMethod("back");method.setAccessible(true);method.invoke(search);
                assertEquals("命中",input.getText().toString());assertNotNull(dialog.getWindow().getDecorView().findViewWithTag("search-result:7"));
                // Account changes dismiss the search before any old content can be shown again.
                field=ChatSession.class.getDeclaredField("connectionGeneration");field.setAccessible(true);field.setInt(session,session.connectionStamp()+1);search.changed();assertFalse(dialog.isShowing());
            }finally{if(search!=null)search.close();controller.pause().stop().destroy();}
        }
    }
    private static String allText(android.view.View view){
        String value=view instanceof TextView?((TextView)view).getText().toString():"";
        if(view instanceof android.view.ViewGroup group)for(int i=0;i<group.getChildCount();i++)value+=" "+allText(group.getChildAt(i));return value;
    }
    private static void drain(BooleanSupplier done)throws Exception{
        for(int i=0;i<600;i++){Shadows.shadowOf(Looper.getMainLooper()).idle();if(done.getAsBoolean()){Shadows.shadowOf(Looper.getMainLooper()).idle();return;}Thread.sleep(5);}
        fail("search response did not arrive");
    }
    private static String message(long id,String text){return "{\"id\":"+id+",\"clientMessageId\":\"fixture\",\"deviceId\":\"fixture\",\"sender\":\"Alice\",\"platform\":\"ios\",\"text\":\""+text+"\",\"createdAt\":1000,\"conversationId\":\"shared\",\"role\":\"user\"}";}
    private static String page(long id,String text){return "{\"results\":[{\"message\":"+message(id,text)+",\"conversationName\":\"设备群聊\"}],\"hasMore\":false,\"nextBefore\":null}";}
    private static String context(long revision){return "{\"messages\":["+message(7,"原始上下文")+"],\"hasOlder\":false,\"hasNewer\":false,\"historyRevision\":"+revision+"}";}
    interface Reply {String get(String path)throws Exception;}
    private static final class Fixture implements AutoCloseable {
        final ServerSocket server;final ExecutorService pool=Executors.newCachedThreadPool();
        final java.util.concurrent.atomic.AtomicInteger authorized=new java.util.concurrent.atomic.AtomicInteger(),completed=new java.util.concurrent.atomic.AtomicInteger();
        Fixture(Reply reply)throws Exception{
            server=new ServerSocket(0,10,InetAddress.getByName("127.0.0.1"));
            pool.submit(()->{while(!server.isClosed())try{Socket socket=server.accept();pool.submit(()->{
                try(socket){socket.setSoTimeout(5000);var input=new BufferedReader(new InputStreamReader(socket.getInputStream(),StandardCharsets.UTF_8));String line=input.readLine(),header;
                    while(!(header=input.readLine()).isEmpty())if(header.equals("Authorization: Bearer chat_search_test"))authorized.incrementAndGet();
                    byte[] body=reply.get(line.split(" ")[1]).getBytes(StandardCharsets.UTF_8);var output=socket.getOutputStream();
                    output.write(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "+body.length+"\r\n\r\n").getBytes(StandardCharsets.US_ASCII));output.write(body);output.flush();completed.incrementAndGet();
                }catch(Exception ignored){} });}catch(IOException ignored){} });
        }
        String url(){return "http://127.0.0.1:"+server.getLocalPort();}
        public void close()throws Exception{server.close();pool.shutdownNow();}
    }
}
