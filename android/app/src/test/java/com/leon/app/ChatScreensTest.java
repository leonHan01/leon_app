package com.leon.app;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.view.View;
import android.widget.EditText;
import android.widget.TextView;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.util.List;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35, qualifiers="w360dp-h780dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class ChatScreensTest {
    private ActivityController<MainActivity> controller;
    private MainActivity activity;
    private ChatSession session;

    @Before public void start() throws Exception {
        controller=Robolectric.buildActivity(MainActivity.class).setup();activity=controller.get();
        Field field=MainActivity.class.getDeclaredField("session");field.setAccessible(true);session=(ChatSession)field.get(activity);session.stop();
        session.agents.add(agent("luna","Luna"));
        session.agents.add(agent("sol","Sol"));
        session.agents.add(agent("terra","Terra"));
        session.conversations.add(room("direct:luna","Luna","direct","luna"));
        session.conversations.add(room("direct:sol","Sol","direct","sol"));
        session.conversations.add(room("shared","设备群聊","group",""));
        session.conversations.add(room("group:ideas","灵感讨论室","group",""));
        session.notifyChanged();
    }
    @After public void finish(){controller.pause().stop().destroy();}

    @Test public void directoriesOpenDedicatedChatsAndPreserveDrafts() {
        assertEquals(View.VISIBLE,view(R.id.home_screen).getVisibility());
        assertEquals(View.GONE,view(R.id.chat_screen).getVisibility());
        view(R.id.tab_agents).performClick();
        assertNull(activity.getWindow().getDecorView().findViewWithTag("group:shared"));
        tagged("agent:luna").performClick();
        assertChat("Luna");assertFalse(view(R.id.tab_agents).isShown());
        input().setText("Luna 的草稿");
        activity.onBackPressed();assertTrue(view(R.id.tab_agents).isSelected());
        tagged("agent:sol").performClick();assertChat("Sol");assertEquals("",input().getText().toString());
        input().setText("Sol 的草稿");activity.onBackPressed();
        tagged("agent:luna").performClick();assertEquals("Luna 的草稿",input().getText().toString());
        activity.onBackPressed();view(R.id.tab_groups).performClick();
        assertNull(activity.getWindow().getDecorView().findViewWithTag("agent:luna"));
        tagged("group:shared").performClick();assertChat("设备群聊");
        activity.onBackPressed();assertTrue(view(R.id.tab_groups).isSelected());
    }

    @Test public void attachmentDrawerClosesBeforeLeavingChat() {
        view(R.id.tab_agents).performClick();tagged("agent:luna").performClick();
        assertEquals(View.GONE,view(R.id.chat_extras).getVisibility());
        view(R.id.chat_add).performClick();assertEquals(View.VISIBLE,view(R.id.chat_extras).getVisibility());
        activity.onBackPressed();assertChat("Luna");assertEquals(View.GONE,view(R.id.chat_extras).getVisibility());
        activity.onBackPressed();assertEquals(View.VISIBLE,view(R.id.home_screen).getVisibility());
        view(R.id.tab_settings).performClick();assertTrue(view(R.id.connection_settings).isShown());
        assertFalse(input().isShown());
    }

    @Test public void conversationCacheRestoresOnlyItsOwnHistory() throws Exception {
        session.select("direct:luna");session.messages.add(message(1,"luna","Luna","历史消息",false));
        session.initialLoaded=true;session.hasOlder=true;session.select("direct:sol");
        assertTrue(session.messages.isEmpty());session.messages.add(message(2,"sol","Sol","另一个会话",false));
        session.select("direct:luna");assertEquals(1,session.messages.size());assertEquals("历史消息",session.messages.get(0).text);
        assertTrue(session.initialLoaded);assertTrue(session.hasOlder);
    }

    @Test public void renderSmallPhoneScreens() throws Exception {
        session.connected=true;session.status="已连接 · 自动同步";
        view(R.id.tab_agents).performClick();snapshot("agents");
        view(R.id.tab_groups).performClick();snapshot("groups");
        view(R.id.tab_settings).performClick();snapshot("settings");
        view(R.id.tab_agents).performClick();tagged("agent:luna").performClick();
        session.messages.add(message(1,"luna","我","帮我安排一个轻松的周末",true));
        session.messages.add(message(2,"luna","Luna","当然，给自己留一点放松的时间。\n\n**周六**\n- 上午去公园散步\n- 下午读一本喜欢的书\n\n**周日**\n和朋友吃顿饭，或者做一道新菜。",false));
        session.messages.add(message(3,"luna","我","不错，就这么安排！",true));
        session.revision++;session.notifyChanged();snapshot("chat");
        input().setText("好的");snapshot("chat-composing");
        input().setText("");view(R.id.chat_add).performClick();snapshot("chat-attachments");
    }

    private void snapshot(String name) throws Exception {
        View root=activity.findViewById(android.R.id.content);int width=360,height=756;
        root.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(height,View.MeasureSpec.EXACTLY));
        root.layout(0,0,width,height);
        if(name.startsWith("chat")){
            assertEquals("Luna",((TextView)view(R.id.chat_title)).getText().toString());
            assertTrue("Chat title height: "+view(R.id.chat_title).getHeight(),view(R.id.chat_title).getHeight()>0);
            TextView t=(TextView)view(R.id.chat_title);System.out.println("TITLE layout="+t.getLayout().getWidth()+" x="+t.getLayout().getLineLeft(0)+" ellipsis="+t.getLayout().getEllipsisCount(0)+" length="+t.getLayout().getText()+" scroll="+t.getScrollX()+" alpha="+t.getAlpha()+" paint="+t.getPaint().getColor());
            assertTrue(input().getWidth()>160);assertTrue(input().getHeight()>=38);
            assertTrue(view(R.id.chat_add).getWidth()>=40);
            assertTrue(view(R.id.chat_title).getWidth()>160);
        }
        Bitmap bitmap=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888);root.draw(new Canvas(bitmap));
        File directory=new File("build/outputs/ui-previews");assertTrue(directory.isDirectory()||directory.mkdirs());
        try(FileOutputStream out=new FileOutputStream(new File(directory,name+".png"))){bitmap.compress(Bitmap.CompressFormat.PNG,100,out);}
        bitmap.recycle();
    }
    private void assertChat(String title){assertEquals(View.VISIBLE,view(R.id.chat_screen).getVisibility());assertEquals(View.GONE,view(R.id.home_screen).getVisibility());assertEquals(title,((TextView)view(R.id.chat_title)).getText().toString());}
    private View view(int id){return activity.findViewById(id);}
    private View tagged(String tag){View view=activity.getWindow().getDecorView().findViewWithTag(tag);assertNotNull(tag,view);return view;}
    private EditText input(){return (EditText)view(R.id.chat_input);}
    private MessageApi.Agent agent(String id,String name) throws Exception {return new MessageApi.Agent(new JSONObject().put("id",id).put("name",name).put("handle",id).put("provider","openai").put("avatarId",id).put("enabled",true));}
    private MessageApi.Conversation room(String id,String name,String kind,String agentId) throws Exception {return new MessageApi.Conversation(new JSONObject().put("id",id).put("name",name).put("kind",kind).put("agentId",agentId).put("agentIds",new JSONArray(kind.equals("direct")?List.of(agentId):List.of("luna","sol","terra"))));}
    private MessageApi.Message message(long id,String agent,String sender,String text,boolean mine) throws Exception {return new MessageApi.Message(new JSONObject().put("id",id).put("createdAt",1795053600000L+id*1000).put("clientMessageId","preview-"+id).put("deviceId",mine?session.deviceId:"preview-assistant").put("sender",sender).put("platform",mine?"android":"agent").put("text",text).put("conversationId","direct:"+agent).put("role",mine?"user":"assistant").put("agentId",mine?"":agent));}
}
