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

    @Test public void signedOutSettingsOffersUsernameRegistration(){
        view(R.id.tab_settings).performClick();
        view(R.id.connection_settings).performClick();
        var dialog=(android.app.AlertDialog)org.robolectric.shadows.ShadowDialog.getLatestDialog();
        assertNotNull(dialog);
        assertTrue(dialog.isShowing());
        assertEquals("继续",dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).getText().toString());
        // The user can cancel the registration dialog without changing the local account.
        dialog.getButton(android.app.AlertDialog.BUTTON_NEGATIVE).performClick();
        assertNull(session.user);
    }

    @Test public void directoriesOpenDedicatedChatsAndPreserveDrafts() {
        assertEquals(View.VISIBLE,view(R.id.home_screen).getVisibility());
        assertEquals(View.GONE,view(R.id.chat_screen).getVisibility());
        view(R.id.tab_agents).performClick();
        assertNull(activity.getWindow().getDecorView().findViewWithTag("group:shared"));
        openAgentChat("luna");
        assertChat("Luna");assertFalse(view(R.id.tab_agents).isShown());
        input().setText("Luna 的草稿");
        backToDirectory();assertTrue(view(R.id.tab_agents).isSelected());
        openAgentChat("sol");assertChat("Sol");assertEquals("",input().getText().toString());
        input().setText("Sol 的草稿");backToDirectory();
        openAgentChat("luna");assertEquals("Luna 的草稿",input().getText().toString());
        backToDirectory();view(R.id.tab_groups).performClick();
        assertNull(activity.getWindow().getDecorView().findViewWithTag("agent:luna"));
        tagged("group:shared").performClick();assertChat("设备群聊");
        activity.onBackPressed();assertTrue(view(R.id.tab_groups).isSelected());
    }

    @Test public void attachmentDrawerClosesBeforeLeavingChat() {
        view(R.id.tab_agents).performClick();openAgentChat("luna");
        assertEquals(View.GONE,view(R.id.chat_extras).getVisibility());
        view(R.id.chat_add).performClick();assertEquals(View.VISIBLE,view(R.id.chat_extras).getVisibility());
        activity.onBackPressed();assertChat("Luna");assertEquals(View.GONE,view(R.id.chat_extras).getVisibility());
        backToDirectory();assertEquals(View.VISIBLE,view(R.id.home_screen).getVisibility());
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

    @Test public void failedNoticesCanBeDismissedAndRestoredWithoutRemovingMessages() throws Exception {
        view(R.id.tab_agents).performClick();openAgentChat("sol");
        session.messages.add(message(10,"sol","我","保留这条消息",true));
        for(int i=1;i<=3;i++)session.jobs.add(new MessageApi.Job(new JSONObject().put("messageId",i).put("agentId","sol").put("agentName","Sol").put("status","FAILED").put("error","模型请求超时，请确认后手动重试")));
        session.revision++;session.notifyChanged();
        tagged("dismiss-job:2:sol").performClick();
        assertEquals(2,session.visibleJobs().size());assertEquals(3,session.jobs.size());assertEquals(1,session.messages.size());
        assertNull(activity.getWindow().getDecorView().findViewWithTag("dismiss-job:2:sol"));
        assertNotNull(tagged("dismiss-job:1:sol"));assertNotNull(tagged("dismiss-job:3:sol"));
        tagged("restore-dismissed-jobs").performClick();assertEquals(3,session.visibleJobs().size());
        assertNotNull(tagged("dismiss-job:2:sol"));
    }

    @Test public void compressionNoticeStaysAtItsPlaceInTheTimeline() throws Exception {
        view(R.id.tab_agents).performClick();openAgentChat("sol");
        session.messages.add(message(1,"sol","Sol","压缩前",false));
        session.messages.add(message(3,"sol","Sol","压缩后",false));
        session.contextOperations=new JSONArray().put(new JSONObject().put("id","compact-1").put("agentName","Sol").put("status","SUCCEEDED").put("result","压缩完成").put("createdAt",1795053602000L));
        session.revision++;session.notifyChanged();
        Field field=MainActivity.class.getDeclaredField("timeline");field.setAccessible(true);
        android.view.ViewGroup timeline=(android.view.ViewGroup)field.get(activity);
        assertTrue(timelineIndex(timeline,"压缩前") < timelineIndex(timeline,"压缩完成"));
        assertTrue(timelineIndex(timeline,"压缩完成") < timelineIndex(timeline,"压缩后"));
    }

    @Test public void failedReplyNoticeFollowsItsTriggeringMessage() throws Exception {
        view(R.id.tab_agents).performClick();openAgentChat("sol");
        session.messages.add(message(1,"sol","我","触发失败的消息",true));
        session.messages.add(message(3,"sol","我","后来的消息",true));
        session.jobs.add(new MessageApi.Job(new JSONObject().put("messageId",1).put("agentId","sol").put("agentName","Sol").put("status","FAILED").put("error","回复失败")));
        session.revision++;session.notifyChanged();
        Field field=MainActivity.class.getDeclaredField("timeline");field.setAccessible(true);
        android.view.ViewGroup timeline=(android.view.ViewGroup)field.get(activity);
        assertTrue(timelineIndex(timeline,"触发失败的消息") < timelineIndex(timeline,"回复失败"));
        assertTrue(timelineIndex(timeline,"回复失败") < timelineIndex(timeline,"后来的消息"));
        assertNotNull(tagged("dismiss-job:1:sol"));
    }

    private int timelineIndex(android.view.ViewGroup timeline,String text) {
        for(int i=0;i<timeline.getChildCount();i++)if(containsText(timeline.getChildAt(i),text))return i;
        fail("Missing timeline text: "+text);return -1;
    }
    private boolean containsText(View view,String text) {
        if(view instanceof TextView && ((TextView)view).getText().toString().contains(text))return true;
        if(view instanceof android.view.ViewGroup){android.view.ViewGroup group=(android.view.ViewGroup)view;for(int i=0;i<group.getChildCount();i++)if(containsText(group.getChildAt(i),text))return true;}
        return false;
    }

    @Test public void quickCommandsFitSmallScreensAndAgentAvatarListsOnlyItsConversations() throws Exception {
        session.conversations.add(room("thread:one","Luna 的周末计划","direct","luna"));
        view(R.id.tab_agents).performClick();tagged("agent-avatar:luna").performClick();
        assertChat("Luna");openProfileFromChat("luna","Luna");
        assertTrue(view(R.id.agent_detail_screen).isShown());
        assertNotNull(tagged("agent-history:direct:luna"));assertNotNull(tagged("agent-history:thread:one"));
        assertNull(activity.getWindow().getDecorView().findViewWithTag("agent-history:direct:sol"));
        tagged("agent-history:thread:one").performClick();assertChat("Luna 的周末计划");
        session.select("direct:luna");view(R.id.chat_add).performClick();
        for(String command:List.of("compact","context","new","load","clear"))assertTrue(tagged("chat-tool:"+command).isShown());
        assertNull(activity.getWindow().getDecorView().findViewWithTag("chat-tool:threads"));
        assertNull(activity.getWindow().getDecorView().findViewWithTag("chat-tool:backup"));
        snapshot("chat-quick-commands");
        for(String command:List.of("compact","context","new","load","clear")){
            View button=tagged("chat-tool:"+command);assertTrue(button.getWidth()>=68);assertTrue(button.getHeight()>=48);
            int[] position=new int[2];button.getLocationOnScreen(position);assertTrue(position[0]>=0);assertTrue(position[0]+button.getWidth()<=360);
        }
    }

    @Test public void renderSmallPhoneScreens() throws Exception {
        session.connected=true;session.status="已连接 · 自动同步";
        view(R.id.tab_agents).performClick();snapshot("agents");
        view(R.id.tab_groups).performClick();snapshot("groups");
        view(R.id.tab_settings).performClick();snapshot("settings");
        view(R.id.tab_agents).performClick();openAgentChat("luna");
        session.messages.add(message(1,"luna","我","帮我安排一个轻松的周末",true));
        session.messages.add(message(2,"luna","Luna","当然，给自己留一点放松的时间。\n\n# 周末安排\n\n| 星期 | 上午 | 下午 |\n| --- | --- | --- |\n| 周六 | 散步 | 读书 |\n| 周日 | 做菜 | 休息 |\n\n和朋友吃顿饭，或者做一道新菜。",false));
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
            TextView title=(TextView)view(R.id.chat_title);
            assertTrue("Centered title must remain inside the header",title.getLayout().getLineRight(0)<=title.getWidth());
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
    @Test public void agentDetailsShowProfileWithoutOpeningOrCreatingAConversation() throws Exception {
        session.conversations.add(room("thread:one","周末计划","direct","luna"));
        session.conversations.add(room("group:luna","包含 Luna 的群聊","group","luna"));
        view(R.id.tab_agents).performClick();tagged("agent:luna").performClick();assertChat("Luna");
        input().setText("返回后保留草稿");String selected=session.selectedConversation;int count=session.conversations.size();
        openProfileFromChat("luna","Luna");assertEquals(count,session.conversations.size());
        assertNull(org.robolectric.shadows.ShadowDialog.getLatestDialog());
        assertTrue(view(R.id.agent_detail_screen).isShown());assertFalse(view(R.id.home_screen).isShown());
        assertFalse(view(R.id.chat_screen).isShown());assertEquals(selected,session.selectedConversation);
        assertEquals("Luna",((TextView)view(R.id.agent_detail_name)).getText().toString());
        assertEquals("帮你梳理思路，规划轻松的日常。",((TextView)view(R.id.agent_detail_description)).getText().toString());
        assertEquals("openai · test-model",((TextView)view(R.id.agent_detail_model)).getText().toString());
        assertNull(activity.getWindow().getDecorView().findViewWithTag("agent-history:direct:sol"));
        assertNull(activity.getWindow().getDecorView().findViewWithTag("agent-history:group:luna"));
        snapshot("agent-details");view(R.id.agent_detail_back).performClick();assertChat("Luna");
        assertEquals("返回后保留草稿",input().getText().toString());
        tagged("message-agent-avatar:luna").performClick();tagged("agent-history:thread:one").performClick();assertChat("周末计划");
        activity.onBackPressed();assertTrue(view(R.id.home_screen).isShown());
    }
    @Test public void oldAgentResponsesAndEmptyHistoriesHaveClearFallbacks() throws Exception {
        var old=new MessageApi.Agent(new JSONObject().put("id","legacy").put("name","旧版助手").put("handle","legacy").put("provider","openai").put("enabled",true));
        session.agents.add(old);session.notifyChanged();view(R.id.tab_agents).performClick();openAgentChat("luna");openProfileFromChat("legacy","旧版助手");
        assertEquals("暂无介绍",((TextView)view(R.id.agent_detail_description)).getText().toString());
        assertEquals("openai · 未提供模型信息",((TextView)view(R.id.agent_detail_model)).getText().toString());
        assertEquals(0,session.agentConversations("legacy").size());
        assertNull(activity.getWindow().getDecorView().findViewWithTag("agent-history:direct:luna"));
        controller.recreate();activity=controller.get();assertTrue(view(R.id.agent_detail_screen).isShown());
        assertEquals("旧版助手",((TextView)view(R.id.agent_detail_name)).getText().toString());
        activity.onBackPressed();assertChat("Luna");
    }
    @Test public void groupMessageAvatarOpensItsAgentAndReturnsToOriginalGroup() throws Exception {
        view(R.id.tab_groups).performClick();tagged("group:shared").performClick();assertChat("设备群聊");
        input().setText("群聊草稿");openProfileFromChat("sol","Sol");
        assertEquals("Sol",((TextView)view(R.id.agent_detail_name)).getText().toString());
        assertEquals("shared",session.selectedConversation);
        assertNotNull(tagged("agent-history:direct:sol"));
        assertNull(activity.getWindow().getDecorView().findViewWithTag("agent-history:direct:luna"));
        activity.onBackPressed();assertChat("设备群聊");assertEquals("群聊草稿",input().getText().toString());
    }
    private void openProfileFromChat(String id,String name) throws Exception {
        session.messages.add(message(50,id,name,"点击头像查看详情",false));session.revision++;session.notifyChanged();
        tagged("message-agent-avatar:"+id).performClick();
    }
    private void openAgentChat(String id){tagged("agent:"+id).performClick();assertTrue(view(R.id.chat_screen).isShown());assertFalse(view(R.id.agent_detail_screen).isShown());}
    private void backToDirectory(){activity.onBackPressed();assertTrue(view(R.id.home_screen).isShown());}
    private void assertChat(String title){assertEquals(View.VISIBLE,view(R.id.chat_screen).getVisibility());assertEquals(View.GONE,view(R.id.home_screen).getVisibility());assertEquals(title,((TextView)view(R.id.chat_title)).getText().toString());}
    private View view(int id){return activity.findViewById(id);}
    private View tagged(String tag){View view=activity.getWindow().getDecorView().findViewWithTag(tag);assertNotNull(tag,view);return view;}
    private EditText input(){return (EditText)view(R.id.chat_input);}
    private MessageApi.Agent agent(String id,String name) throws Exception {return new MessageApi.Agent(new JSONObject().put("id",id).put("name",name).put("handle",id).put("provider","openai").put("model","test-model").put("description","帮你梳理思路，规划轻松的日常。").put("avatarId",id).put("enabled",true));}
    private MessageApi.Conversation room(String id,String name,String kind,String agentId) throws Exception {return new MessageApi.Conversation(new JSONObject().put("id",id).put("name",name).put("kind",kind).put("agentId",agentId).put("agentIds",new JSONArray(kind.equals("direct")?List.of(agentId):List.of("luna","sol","terra"))));}
    private MessageApi.Message message(long id,String agent,String sender,String text,boolean mine) throws Exception {return new MessageApi.Message(new JSONObject().put("id",id).put("createdAt",1795053600000L+id*1000).put("clientMessageId","preview-"+id).put("deviceId",mine?session.deviceId:"preview-assistant").put("sender",sender).put("platform",mine?"android":"agent").put("text",text).put("conversationId","direct:"+agent).put("role",mine?"user":"assistant").put("agentId",mine?"":agent));}
}
