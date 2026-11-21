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

    @Test public void newConversationStartsAtLatestAndCachedReturnRestoresReadingPosition() throws Exception {
        view(R.id.tab_agents).performClick();openAgentChat("luna");fillMessages(100,45);layoutAndIdle();assertLatestVisible();
        chatTimeline().scrollTo(0,chatTimeline().getChildAt(0).getHeight()/2);int saved=chatTimeline().getScrollY();assertTrue(saved>0);backToDirectory();
        openAgentChat("luna");layoutAndIdle();assertEquals(saved,chatTimeline().getScrollY());
        backToDirectory();openAgentChat("sol");fillMessages(200,30);layoutAndIdle();assertLatestVisible();
        backToDirectory();openAgentChat("luna");layoutAndIdle();assertEquals(saved,chatTimeline().getScrollY());
        tagged("message-agent-avatar:luna").performClick();activity.onBackPressed();layoutAndIdle();assertEquals(saved,chatTimeline().getScrollY());
    }
    @Test public void delayedHistoryFollowsLatestButReadingAndPrependingStayInPlace() throws Exception {
        view(R.id.tab_agents).performClick();openAgentChat("luna");layoutAndIdle();fillMessages(100,45);layoutAndIdle();assertLatestVisible();
        chatTimeline().scrollTo(0,0);session.messages.add(message(150,"luna","Luna","稍后收到的新回复",false));session.revision++;session.notifyChanged();layoutAndIdle();assertEquals(0,chatTimeline().getScrollY());
        int[] before=new int[2];tagged("message-actions:100").getLocationOnScreen(before);
        session.messages.add(0,message(50,"luna","Luna","更早的聊天记录",false));session.revision++;session.notifyChanged();layoutAndIdle();
        int[] after=new int[2];tagged("message-actions:100").getLocationOnScreen(after);assertTrue(chatTimeline().getScrollY()>0);assertEquals(before[1],after[1]);
    }
    @Test public void lateContentLayoutKeepsLatestOnlyWhenFollowingBottom() throws Exception {
        view(R.id.tab_agents).performClick();openAgentChat("luna");fillMessages(100,35);layoutAndIdle();assertLatestVisible();
        android.widget.LinearLayout rows=(android.widget.LinearLayout)chatTimeline().getChildAt(0);View expanded=new View(activity);rows.addView(expanded,new android.widget.LinearLayout.LayoutParams(-1,300));layoutAndIdle();assertLatestVisible();
        chatTimeline().scrollTo(0,0);rows.addView(new View(activity),new android.widget.LinearLayout.LayoutParams(-1,300));layoutAndIdle();assertEquals(0,chatTimeline().getScrollY());
    }
    private android.widget.ScrollView chatTimeline(){return (android.widget.ScrollView)tagged("chat-timeline");}
    private void fillMessages(int start,int count)throws Exception {for(int i=0;i<count;i++)session.messages.add(message(start+i,session.selectedConversation.endsWith("sol")?"sol":"luna","助手","这是一段用于验证进入会话滚动位置的聊天记录，内容需要正常换行。第 "+i+" 条。",false));session.initialLoaded=true;session.revision++;session.notifyChanged();}
    private void layoutAndIdle(){View root=activity.findViewById(android.R.id.content);for(int i=0;i<5;i++){root.measure(View.MeasureSpec.makeMeasureSpec(360,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(756,View.MeasureSpec.EXACTLY));root.layout(0,0,360,756);org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(16));}}
    private void assertLatestVisible(){android.widget.ScrollView view=chatTimeline();int range=view.getChildAt(0).getHeight()-view.getHeight();assertTrue("Fixture must need scrolling",range>100);assertTrue("Latest message must be visible: "+view.getScrollY()+"/"+range,Math.abs(range-view.getScrollY())<=1);}

    @Test public void longHistoryCacheRetainsReadingAnchorAndClearRemovesIt()throws Exception {
        session.select("direct:luna");for(int i=1;i<=500;i++)session.messages.add(message(i,"luna","Luna","消息 "+i,false));session.initialLoaded=true;
        session.scrollPositions.put("direct:luna",new ChatSession.ScrollPosition(20,-10,500));session.select("direct:sol");session.select("direct:luna");
        assertEquals(300,session.messages.size());assertTrue(session.messages.stream().anyMatch(m->m.id==20));
        session.clearLocalHistory("direct:luna",2);assertFalse(session.scrollPositions.containsKey("direct:luna"));
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
        for(String command:List.of("compact","context","new","threads"))assertTrue(tagged("chat-tool:"+command).isShown());
        assertNull(activity.getWindow().getDecorView().findViewWithTag("chat-tool:load"));
        assertNull(activity.getWindow().getDecorView().findViewWithTag("chat-tool:clear"));
        assertNull(activity.getWindow().getDecorView().findViewWithTag("chat-tool:backup"));
        snapshot("chat-quick-commands");
        for(String command:List.of("compact","context","new","threads")){
            View button=tagged("chat-tool:"+command);assertTrue(button.getWidth()>=64);assertTrue(button.getHeight()>=48);
            int[] position=new int[2];button.getLocationOnScreen(position);assertTrue(position[0]>=0);assertTrue(position[0]+button.getWidth()<=((View)button.getParent()).getWidth()+12);
            int[] first=new int[2];tagged("chat-tool:compact").getLocationOnScreen(first);assertEquals("Quick commands must share one row",first[1],position[1]);
        }
        input().setText("返回后继续输入");int count=session.conversations.size();
        tagged("chat-tool:threads").performClick();
        assertTrue(view(R.id.agent_detail_screen).isShown());assertNotNull(tagged("agent-history:thread:one"));
        assertEquals("direct:luna",session.selectedConversation);assertEquals(count,session.conversations.size());
        view(R.id.agent_detail_back).performClick();assertChat("Luna");
        assertEquals("返回后继续输入",input().getText().toString());assertEquals(View.GONE,view(R.id.chat_extras).getVisibility());
    }

    @Test public void groupConversationListSelectsAgentWithoutCreatingOrSwitchingChat() {
        view(R.id.tab_groups).performClick();tagged("group:shared").performClick();
        input().setText("群聊草稿");int count=session.conversations.size();
        view(R.id.chat_add).performClick();tagged("chat-tool:threads").performClick();
        assertEquals(View.GONE,view(R.id.chat_extras).getVisibility());
        var chooser=(android.app.AlertDialog)org.robolectric.shadows.ShadowDialog.getLatestDialog();
        assertNotNull(chooser);chooser.getListView().performItemClick(null,1,1);
        assertTrue(view(R.id.agent_detail_screen).isShown());assertEquals("Sol",((TextView)view(R.id.agent_detail_name)).getText().toString());
        assertEquals("shared",session.selectedConversation);assertEquals(count,session.conversations.size());
        view(R.id.agent_detail_back).performClick();assertChat("设备群聊");assertEquals("群聊草稿",input().getText().toString());
    }

    @Test public void longPressQuoteKeepsDraftAndCancelRemovesOnlyTheReference()throws Exception{
        view(R.id.tab_agents).performClick();openAgentChat("luna");
        var original=message(71,"luna","Luna","这是一条可以引用的消息",false);session.messages.add(original);session.revision++;session.notifyChanged();
        input().setText("已有草稿");tagged("message-actions:71").performLongClick();
        var menu=(android.app.AlertDialog)org.robolectric.shadows.ShadowDialog.getLatestDialog();
        assertEquals("引用",((TextView)menu.getListView().getAdapter().getView(1,null,menu.getListView())).getText().toString());
        menu.getListView().performItemClick(null,1,1);assertEquals(71,session.quotedMessage.id);assertTrue(tagged("quote-preview").isShown());assertEquals("已有草稿",input().getText().toString());
        snapshot("chat-quoted");
        session.select("direct:sol");assertNull(session.quotedMessage);session.select("direct:luna");assertEquals(71,session.quotedMessage.id);
        tagged("cancel-quote").performClick();assertNull(session.quotedMessage);assertEquals("已有草稿",input().getText().toString());
    }
    @Test public void imageOnlyAndRichMessagesExposeTheSameMessageActions()throws Exception{
        view(R.id.tab_agents).performClick();openAgentChat("luna");
        var rich=message(72,"luna","Luna","```java\nint x=1;\n```",false);session.messages.add(rich);
        var image=new JSONObject().put("id",73).put("createdAt",1795053601000L).put("clientMessageId","fixture-image").put("deviceId","other").put("sender","Luna").put("platform","agent").put("text","").put("conversationId","direct:luna").put("role","assistant").put("agentId","luna").put("images",new JSONArray().put(new JSONObject().put("id","11111111-1111-4111-8111-111111111111")));
        session.messages.add(new MessageApi.Message(image));session.revision++;session.notifyChanged();
        for(long id:new long[]{72,73}){tagged("message-actions:"+id).performLongClick();var menu=(android.app.AlertDialog)org.robolectric.shadows.ShadowDialog.getLatestDialog();assertEquals(4,menu.getListView().getCount());assertEquals("从这里创建分支",menu.getListView().getAdapter().getItem(3));menu.dismiss();}
        activity.onBackPressed();view(R.id.tab_settings).performClick();assertNotNull(tagged("my-favorites"));
    }

    @Test public void branchDialogKeepsSourceDraftAndRejectsAnEmptyName()throws Exception {
        view(R.id.tab_agents).performClick();openAgentChat("luna");
        Field client=ChatSession.class.getDeclaredField("api");client.setAccessible(true);client.set(session,new MessageApi("https://branch.invalid","chat_fixture"));
        var point=message(74,"luna","Luna","可以另开讨论的消息",false);session.messages.add(point);session.revision++;session.notifyChanged();
        input().setText("原会话草稿");tagged("message-actions:74").performLongClick();
        var menu=(android.app.AlertDialog)org.robolectric.shadows.ShadowDialog.getLatestDialog();
        assertEquals("从这里创建分支",menu.getListView().getAdapter().getItem(3));menu.getListView().performItemClick(null,3,3);
        var prompt=(android.app.AlertDialog)org.robolectric.shadows.ShadowDialog.getLatestDialog();assertTrue(prompt.isShowing());
        var name=(EditText)prompt.getWindow().getDecorView().findViewWithTag("branch_name");assertNotNull(name);assertTrue(name.getText().toString().contains("分支"));
        name.setText("");prompt.getButton(android.app.AlertDialog.BUTTON_POSITIVE).performClick();assertNotNull(name.getError());assertFalse(session.toolsBusy);
        prompt.getButton(android.app.AlertDialog.BUTTON_NEGATIVE).performClick();
        assertEquals("direct:luna",session.selectedConversation);assertEquals("原会话草稿",input().getText().toString());
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
        if(name.equals("chat-quick-commands")){
            View panel=view(R.id.chat_extras);Bitmap artwork=Bitmap.createBitmap(panel.getWidth(),panel.getHeight(),Bitmap.Config.ARGB_8888);
            Canvas canvas=new Canvas(artwork);canvas.drawColor(ChatUi.BAR);panel.draw(canvas);
            try(FileOutputStream out=new FileOutputStream(new File(directory,"quick-panel.png"))){artwork.compress(Bitmap.CompressFormat.PNG,100,out);}
            artwork.recycle();
        }
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
    @Test public void chatMenuOpensCurrentAgentDetailsAndKeepsOtherActions() {
        view(R.id.tab_agents).performClick();openAgentChat("luna");
        input().setText("保留草稿");view(R.id.chat_more).performClick();
        var menu=org.robolectric.shadows.ShadowPopupMenu.getLatestPopupMenu().getMenu();
        assertNotNull(menu.findItem(menu.getItem(0).getItemId()));
        assertEquals("查看 Agent 信息",menu.getItem(0).getTitle().toString());
        assertEquals("查找聊天记录",menu.findItem(R.id.find_chat_history).getTitle().toString());
        assertTrue(java.util.stream.IntStream.range(0,menu.size()).anyMatch(i->menu.getItem(i).getTitle().toString().equals("会话信息")));
        menu.performIdentifierAction(menu.getItem(0).getItemId(),0);
        assertTrue(view(R.id.agent_detail_screen).isShown());
        assertEquals("Luna",((TextView)view(R.id.agent_detail_name)).getText().toString());
        assertEquals("帮你梳理思路，规划轻松的日常。",((TextView)view(R.id.agent_detail_description)).getText().toString());
        assertNotNull(tagged("agent-history:direct:luna"));
        assertNull(activity.getWindow().getDecorView().findViewWithTag("agent-history:direct:sol"));
        activity.onBackPressed();assertChat("Luna");assertEquals("保留草稿",input().getText().toString());
    }
    @Test public void groupMenuChoosesAgentWithoutOpeningAPrivateChat() {
        view(R.id.tab_groups).performClick();tagged("group:shared").performClick();
        input().setText("保留群聊草稿");view(R.id.chat_more).performClick();
        var menu=org.robolectric.shadows.ShadowPopupMenu.getLatestPopupMenu().getMenu();
        assertEquals("查看 Agent 信息",menu.getItem(0).getTitle().toString());
        menu.performIdentifierAction(menu.getItem(0).getItemId(),0);
        var chooser=(android.app.AlertDialog)org.robolectric.shadows.ShadowDialog.getLatestDialog();
        assertNotNull(chooser);
        chooser.getListView().performItemClick(null,1,1);
        assertTrue(view(R.id.agent_detail_screen).isShown());
        assertEquals("Sol",((TextView)view(R.id.agent_detail_name)).getText().toString());
        assertNotNull(tagged("agent-history:direct:sol"));
        assertNull(activity.getWindow().getDecorView().findViewWithTag("agent-history:direct:luna"));
        assertEquals("shared",session.selectedConversation);
        activity.onBackPressed();assertChat("设备群聊");assertEquals("保留群聊草稿",input().getText().toString());
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
    @Test public void ownedGroupChatHasDirectUserAndAgentInvitationEntries()throws Exception{
        session.user=new MessageApi.User("owner","Owner");
        session.conversations.add(new MessageApi.Conversation(new JSONObject().put("id","group:owned").put("name","我的群聊").put("kind","group").put("agentIds",new JSONArray().put("luna")).put("ownerId","owner")));
        session.agents.removeIf(agent->agent.id.equals("terra"));
        session.agents.add(new MessageApi.Agent(new JSONObject().put("id","terra").put("name","Terra").put("handle","terra").put("provider","openai").put("enabled",false)));
        session.notifyChanged();view(R.id.tab_groups).performClick();tagged("group:group:owned").performClick();input().setText("群聊草稿");
        view(R.id.chat_more).performClick();var menu=org.robolectric.shadows.ShadowPopupMenu.getLatestPopupMenu().getMenu();
        assertNotNull(menu.findItem(R.id.chat_invite_users));assertNotNull(menu.findItem(R.id.chat_invite_agents));
        menu.performIdentifierAction(R.id.chat_invite_users,0);
        var users=(android.app.AlertDialog)org.robolectric.shadows.ShadowDialog.getLatestDialog();
        assertNotNull(users.getWindow().getDecorView().findViewWithTag("group_invite_usernames"));users.dismiss();
        menu.performIdentifierAction(R.id.chat_invite_agents,0);
        var agents=(android.app.AlertDialog)org.robolectric.shadows.ShadowDialog.getLatestDialog();
        assertNotNull(agents.getWindow().getDecorView().findViewWithTag("invite-agent:sol"));
        assertNull(agents.getWindow().getDecorView().findViewWithTag("invite-agent:luna"));
        assertNull(agents.getWindow().getDecorView().findViewWithTag("invite-agent:terra"));
        agents.dismiss();assertChat("我的群聊");assertEquals("群聊草稿",input().getText().toString());
        session.user=new MessageApi.User("member","Member");view(R.id.chat_more).performClick();
        menu=org.robolectric.shadows.ShadowPopupMenu.getLatestPopupMenu().getMenu();
        assertNull(menu.findItem(R.id.chat_invite_users));assertNull(menu.findItem(R.id.chat_invite_agents));
        session.user=new MessageApi.User("owner","Leon");session.select("shared");view(R.id.chat_more).performClick();
        menu=org.robolectric.shadows.ShadowPopupMenu.getLatestPopupMenu().getMenu();
        assertNull(menu.findItem(R.id.chat_invite_users));assertNull(menu.findItem(R.id.chat_invite_agents));
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
