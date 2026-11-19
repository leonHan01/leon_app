package com.leon.app;

import java.io.ByteArrayInputStream;
import java.util.List;
import org.json.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=26)
public class ChatToolsStateTest {
    @Test public void backupStreamsAreBoundedOnAndroidEight()throws Exception{
        byte[] input=new byte[100];assertEquals(20,ChatTools.readLimited(new ByteArrayInputStream(input),20).length);
        assertEquals(100,ChatTools.readLimited(new ByteArrayInputStream(input),101).length);
    }
    @Test public void clearingInvalidatesCachedHistoryAndDraftsWithoutTouchingOtherConversations()throws Exception{
        var session=new ChatSession(RuntimeEnvironment.getApplication());
        try{
            session.select("direct:one");session.draft="其他会话草稿";
            session.select("shared");session.draft="应清理的草稿";
            var data=new JSONObject().put("id",1).put("createdAt",100).put("clientMessageId","preview").put("deviceId",session.deviceId).put("sender","我").put("platform","android").put("text","旧消息");
            session.messages.add(new MessageApi.Message(data));session.initialLoaded=true;
            session.select("direct:two");session.select("shared");assertEquals(1,session.messages.size());
            session.clearLocalHistory("shared",1);assertTrue(session.messages.isEmpty());assertEquals("",session.draft);assertFalse(session.initialLoaded);
            session.select("direct:one");assertEquals("其他会话草稿",session.draft);
            session.select("shared");assertTrue(session.messages.isEmpty());assertEquals("",session.draft);
        }finally{session.close();}
    }
    @Test public void pageRetainsRevisionAndCompressionProgress()throws Exception{
        var page=new MessageApi.Page(new JSONObject().put("messages",new JSONArray()).put("hasMore",false).put("historyRevision",42).put("contextOperations",new JSONArray().put(new JSONObject().put("status","RUNNING"))));
        assertEquals(42,page.historyRevision);assertEquals("RUNNING",page.contextOperations.getJSONObject(0).getString("status"));
        var old=new MessageApi.Page(new JSONObject().put("messages",new JSONArray()).put("hasMore",false));assertEquals(-1,old.historyRevision);assertEquals(0,old.contextOperations.length());
    }
}
