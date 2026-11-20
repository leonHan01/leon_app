package com.leon.app;

import android.app.*;
import android.os.*;
import android.content.*;
import android.content.ClipboardManager;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.*;
import android.view.*;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.*;
import org.json.JSONObject;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.*;

public final class MainActivity extends Activity implements ChatSession.Listener {
    private static final int GREEN=ChatUi.GREEN, INK=ChatUi.INK, MUTED=ChatUi.MUTED;
    private ChatSession session;
    private MessageMarkdown markdown;
    private ChatUi ui;
    private ChatTools tools;
    private final ChatNavigation navigation=new ChatNavigation();
    private LinearLayout homeScreen,chatScreen,homeRows,attachmentRows,mentionPanel,mentionRows,extras,agentDetailScreen,agentDetailRows;
    private String agentDetailSignature="";
    private int agentDetailConnection;
    private final EnumMap<ChatNavigation.Tab,LinearLayout> tabViews=new EnumMap<>(ChatNavigation.Tab.class);
    private TextView homeTitle,homeStatus,roomTitle,roomStatus;
    private ImageButton homeAdd,chatAdd;
    private MentionEditText composer;
    private Button send,older,imageButton,mentionButton;
    private ScrollView scroll;
    private LinearLayout timeline;
    private AlertDialog settings;
    private AlertDialog usageDialog;
    private LinearLayout usageContent;
    private String usageSignature="";
    private String renderedConversation="",homeSignature="",attachmentSignature="";
    private long renderedRevision=-1;
    private final List<MessageApi.Agent> mentionCandidates=new ArrayList<>();
    private int mentionIndex;
    private String mentionKey="",dismissedMentionKey="",mentionRenderKey="";

    @Override public void onCreate(Bundle savedState){
        super.onCreate(savedState);
        session=(ChatSession)getLastNonConfigurationInstance();
        if(session==null)session=new ChatSession(getApplicationContext());
        session.listener=this;ui=new ChatUi(this);markdown=new MessageMarkdown(this);
        if(savedState!=null){navigation.restore(savedState.getString("homeTab"),savedState.getBoolean("chat"));navigation.agentId=savedState.getString("agentDetail","");}
        else if(!session.configured())navigation.tab(ChatNavigation.Tab.SETTINGS);
        agentDetailConnection=session.connectionStamp();
        tools=new ChatTools(this,session,room->openGroup(room));
        buildUI();showScreen();
        if(savedState!=null&&savedState.getBoolean("settings"))showSettings();
        if(savedState!=null&&savedState.getBoolean("usage"))showUsage();
    }
    @Override public Object onRetainNonConfigurationInstance(){return session;}
    @Override protected void onStart(){super.onStart();session.start();}
    @Override protected void onStop(){session.stop();super.onStop();}
    @Override protected void onSaveInstanceState(Bundle out){
        out.putString("homeTab",navigation.tab.name());out.putBoolean("chat",navigation.inChat);
        out.putString("agentDetail",navigation.agentId);
        out.putBoolean("usage",usageDialog!=null&&usageDialog.isShowing());
        out.putBoolean("settings",settings!=null&&settings.isShowing());super.onSaveInstanceState(out);
    }
    @Override protected void onDestroy(){RichMarkdownView.releaseTree(findViewById(android.R.id.content));session.listener=null;if(settings!=null)settings.dismiss();if(usageDialog!=null)usageDialog.dismiss();tools.close();if(!isChangingConfigurations())session.close();super.onDestroy();}
    @Override public void onBackPressed(){
        if(navigation.attachments){navigation.attachments=false;showScreen();return;}
        if(navigation.inChat){hideKeyboard();composer.clearFocus();navigation.back();showScreen();return;}
        if(!navigation.agentId.isEmpty()){navigation.back();showScreen();return;}
        super.onBackPressed();
    }

    private void buildUI(){
        LinearLayout root=column();root.setBackgroundColor(ChatUi.BAR);
        getWindow().setStatusBarColor(ChatUi.BAR);getWindow().setNavigationBarColor(ChatUi.BAR);
        int flags=View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
        getWindow().getDecorView().setSystemUiVisibility(flags);
        if(Build.VERSION.SDK_INT>=30){
            getWindow().setDecorFitsSystemWindows(false);
            root.setOnApplyWindowInsetsListener((view,insets)->{
                android.graphics.Insets edges=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.ime());
                view.setPadding(edges.left,edges.top,edges.right,edges.bottom);return insets;
            });
        }
        FrameLayout pages=new FrameLayout(this);root.addView(pages,new LinearLayout.LayoutParams(-1,0,1));
        homeScreen=column();homeScreen.setId(R.id.home_screen);pages.addView(homeScreen,new FrameLayout.LayoutParams(-1,-1));
        buildHome();
        chatScreen=column();chatScreen.setId(R.id.chat_screen);chatScreen.setBackgroundColor(ChatUi.CHAT);
        pages.addView(chatScreen,new FrameLayout.LayoutParams(-1,-1));buildChat();setContentView(root);
        agentDetailScreen=column();agentDetailScreen.setId(R.id.agent_detail_screen);pages.addView(agentDetailScreen,new FrameLayout.LayoutParams(-1,-1));buildAgentDetail();
    }
    private void buildHome(){
        LinearLayout bar=row();bar.setGravity(Gravity.CENTER_VERTICAL);bar.setPadding(dp(18),0,dp(6),0);bar.setBackgroundColor(ChatUi.BAR);
        homeTitle=text("Agents",21,INK);homeTitle.setTypeface(null,Typeface.BOLD);homeTitle.setId(R.id.home_title);
        bar.addView(homeTitle,new LinearLayout.LayoutParams(0,dp(56),1));homeTitle.setGravity(Gravity.CENTER_VERTICAL);
        homeAdd=ui.icon(R.drawable.ic_more,"列表操作");homeAdd.setId(R.id.home_add);homeAdd.setOnClickListener(view->{
            if(navigation.tab==ChatNavigation.Tab.GROUPS)showNewGroup();else showHomeMenu();
        });bar.addView(homeAdd);homeScreen.addView(bar);
        homeScreen.addView(ui.divider(0));
        homeStatus=text("",12,MUTED);homeStatus.setPadding(dp(18),dp(9),dp(18),dp(9));homeStatus.setBackgroundColor(0xFFFFF6E8);homeScreen.addView(homeStatus);
        ScrollView list=new ScrollView(this);list.setFillViewport(true);list.setBackgroundColor(Color.WHITE);
        homeRows=column();list.addView(homeRows,new ScrollView.LayoutParams(-1,-2));homeScreen.addView(list,new LinearLayout.LayoutParams(-1,0,1));
        homeScreen.addView(ui.divider(0));
        LinearLayout tabs=row();tabs.setBackgroundColor(ChatUi.BAR);
        addTab(tabs,ChatNavigation.Tab.AGENTS,"Agents",R.drawable.ic_agents,R.id.tab_agents);
        addTab(tabs,ChatNavigation.Tab.GROUPS,"群聊",R.drawable.ic_groups,R.id.tab_groups);
        addTab(tabs,ChatNavigation.Tab.SETTINGS,"设置",R.drawable.ic_settings,R.id.tab_settings);
        homeScreen.addView(tabs,new LinearLayout.LayoutParams(-1,dp(60)));
    }
    private void addTab(LinearLayout parent,ChatNavigation.Tab tab,String label,int resource,int id){
        LinearLayout item=column();item.setGravity(Gravity.CENTER);item.setId(id);item.setContentDescription(label);
        item.setBackground(ui.ripple(ChatUi.BAR,0));item.setFocusable(true);
        ImageView icon=new ImageView(this);icon.setImageResource(resource);item.addView(icon,new LinearLayout.LayoutParams(dp(24),dp(24)));
        TextView title=text(label,11,MUTED);LinearLayout.LayoutParams tp=new LinearLayout.LayoutParams(-2,-2);tp.topMargin=dp(4);item.addView(title,tp);
        item.setOnClickListener(view->{navigation.tab(tab);homeSignature="";showScreen();});
        parent.addView(item,new LinearLayout.LayoutParams(0,-1,1));tabViews.put(tab,item);
    }
    private void showScreen(){
        boolean detail=!navigation.agentId.isEmpty();
        homeScreen.setVisibility(navigation.inChat||detail?View.GONE:View.VISIBLE);chatScreen.setVisibility(navigation.inChat&&!detail?View.VISIBLE:View.GONE);
        agentDetailScreen.setVisibility(detail?View.VISIBLE:View.GONE);
        extras.setVisibility(navigation.inChat&&!detail&&navigation.attachments?View.VISIBLE:View.GONE);chatAdd.setRotation(navigation.attachments?45:0);
        if(detail){hideMentionSuggestions(false);renderAgentDetail();}
        else if(navigation.inChat){changed();session.refreshImages();}
        else{hideMentionSuggestions(false);renderHome();}
    }
    private void renderHome(){
        String title=navigation.tab==ChatNavigation.Tab.AGENTS?"Agents":navigation.tab==ChatNavigation.Tab.GROUPS?"群聊":"设置";
        homeTitle.setText(title);homeAdd.setVisibility(navigation.tab==ChatNavigation.Tab.SETTINGS?View.GONE:View.VISIBLE);
        homeAdd.setImageResource(navigation.tab==ChatNavigation.Tab.GROUPS?R.drawable.ic_add:R.drawable.ic_more);
        homeAdd.setContentDescription(navigation.tab==ChatNavigation.Tab.GROUPS?"新建群聊":"列表操作");
        homeStatus.setVisibility(navigation.tab==ChatNavigation.Tab.SETTINGS||session.connected?View.GONE:View.VISIBLE);
        homeStatus.setText(session.configured()?session.status:"请先在设置中注册或登录");
        for(var entry:tabViews.entrySet()){
            boolean selected=entry.getKey()==navigation.tab;LinearLayout item=entry.getValue();item.setSelected(selected);
            ((ImageView)item.getChildAt(0)).setImageTintList(ColorStateList.valueOf(selected?GREEN:INK));
            ((TextView)item.getChildAt(1)).setTextColor(selected?GREEN:MUTED);
        }
        StringBuilder signature=new StringBuilder(navigation.tab.name()).append(session.server).append(session.sender).append(session.user).append(session.configured()).append(session.connected).append(session.status);
        for(var agent:session.agents)signature.append(agent.id).append(agent.name).append(agent.handle).append(agent.provider).append(agent.avatarId).append(agent.enabled);
        for(var room:session.conversations)signature.append(room.id).append(room.name).append(room.agentIds);
        if(signature.toString().equals(homeSignature))return;homeSignature=signature.toString();homeRows.removeAllViews();
        if(navigation.tab==ChatNavigation.Tab.AGENTS){
            homeRows.setId(R.id.agent_list);int count=0;
            for(MessageApi.Agent agent:session.agents){
                boolean history=session.conversations.stream().anyMatch(room->room.kind.equals("direct")&&room.agentId.equals(agent.id));
                if(!agent.enabled&&!history)continue;count++;
                addDirectoryRow(avatar(agent.avatarId,48),agent.name,"@"+agent.handle+" · "+(agent.enabled?agent.provider:"已停用"),"agent:"+agent.id,()->openAgent(agent));
            }
            if(count==0)emptyHome("还没有 Agents",session.configured()?"在服务端配置 Agent 后，点这里即可开始私聊。":"先连接服务，查看你的 AI 助手。");
        }else if(navigation.tab==ChatNavigation.Tab.GROUPS){
            homeRows.setId(R.id.group_list);int count=0;
            for(MessageApi.Conversation room:session.conversations)if(!room.kind.equals("direct")){
                count++;ImageView icon=new ImageView(this);icon.setImageResource(R.drawable.ic_groups);icon.setImageTintList(ColorStateList.valueOf(Color.WHITE));
                icon.setPadding(dp(10),dp(10),dp(10),dp(10));icon.setBackground(shape(0xFF62AA88,7));
                addDirectoryRow(icon,room.name,(room.id.equals("shared")||room.id.startsWith("home:"))?"设备消息与 Agent 群聊":room.agentIds.size()+" 位 Agent","group:"+room.id,()->openGroup(room));
            }
            if(count==0)emptyHome("还没有群聊",session.configured()?"点击右上角 ＋，选择 Agents 创建群聊。":"连接服务后即可查看和创建群聊。");
        }else{
            homeRows.setId(R.id.settings_list);renderSettingsPage();
        }
    }
    private void addDirectoryRow(View avatar,String title,String detail,String tag,Runnable action){
        LinearLayout item=row();item.setGravity(Gravity.CENTER_VERTICAL);item.setPadding(dp(16),dp(13),dp(16),dp(13));
        item.setTag(tag);item.setContentDescription(title+"，"+detail);item.setBackground(ui.ripple(Color.WHITE,0));item.setFocusable(true);item.setOnClickListener(view->action.run());
        if(tag.startsWith("agent:")){
            String agentId=tag.substring(6);avatar.setTag("agent-avatar:"+agentId);avatar.setContentDescription("与 "+title+" 聊天");
            avatar.setOnClickListener(view->action.run());
        }
        item.addView(avatar,new LinearLayout.LayoutParams(dp(48),dp(48)));
        LinearLayout labels=column();TextView name=text(title,17,INK);name.setSingleLine();name.setEllipsize(TextUtils.TruncateAt.END);labels.addView(name);
        TextView subtitle=text(detail,12,MUTED);subtitle.setSingleLine();subtitle.setEllipsize(TextUtils.TruncateAt.END);LinearLayout.LayoutParams sp=new LinearLayout.LayoutParams(-1,-2);sp.topMargin=dp(7);labels.addView(subtitle,sp);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(0,-2,1);lp.leftMargin=dp(13);item.addView(labels,lp);
        ImageView arrow=new ImageView(this);arrow.setImageResource(R.drawable.ic_chevron);arrow.setImageTintList(ColorStateList.valueOf(0xFFBBBBBB));item.addView(arrow,new LinearLayout.LayoutParams(dp(18),dp(18)));
        homeRows.addView(item);homeRows.addView(ui.divider(77));
    }
    private void emptyHome(String title,String detail){
        LinearLayout empty=column();empty.setGravity(Gravity.CENTER);empty.setPadding(dp(28),dp(80),dp(28),dp(40));
        TextView heading=text(title,18,INK);empty.addView(heading);TextView message=text(detail,14,MUTED);message.setGravity(Gravity.CENTER);message.setLineSpacing(dp(5),1);
        LinearLayout.LayoutParams mp=new LinearLayout.LayoutParams(-1,-2);mp.topMargin=dp(12);empty.addView(message,mp);
        if(!session.configured()){Button configure=action("前往设置");configure.setOnClickListener(view->{navigation.tab(ChatNavigation.Tab.SETTINGS);homeSignature="";showScreen();});empty.addView(configure);}
        homeRows.addView(empty);
    }
    private void renderSettingsPage(){
        LinearLayout identity=row();identity.setGravity(Gravity.CENTER_VERTICAL);identity.setPadding(dp(20),dp(26),dp(20),dp(26));
        TextView mark=text("L",25,Color.WHITE);mark.setTypeface(null,Typeface.BOLD);mark.setGravity(Gravity.CENTER);mark.setBackground(shape(GREEN,12));identity.addView(mark,new LinearLayout.LayoutParams(dp(58),dp(58)));
        LinearLayout labels=column();TextView name=text("Leon",21,INK);name.setTypeface(null,Typeface.BOLD);labels.addView(name);
        TextView description=text("你的 Agents 与群聊",13,MUTED);LinearLayout.LayoutParams dp=new LinearLayout.LayoutParams(-2,-2);dp.topMargin=dp(7);labels.addView(description,dp);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(0,-2,1);lp.leftMargin=dp(16);identity.addView(labels,lp);homeRows.addView(identity);sectionGap();
        if(session.user==null){
            View login=settingRow("注册或登录","输入 UserName 和服务访问令牌",R.drawable.ic_agents,this::showSettings);
            login.setId(R.id.connection_settings);
        }else{
            View account=settingRow(session.user.username(),session.server,R.drawable.ic_agents,this::confirmLogout);
            account.setId(R.id.connection_settings);
            settingRow("退出登录","",R.drawable.ic_settings,this::confirmLogout);
        }
        View usage=settingRow("Token 用量","查看累计消耗与模型明细",R.drawable.ic_usage,this::showUsage);usage.setId(R.id.token_usage);
        sectionGap();settingRow("连接状态",session.connected?"已连接 · 自动同步":session.status,R.drawable.ic_groups,()->{
            new AlertDialog.Builder(this).setTitle("连接状态").setMessage(session.status+"\n\n应用在前台时自动同步。退出后消息保留在服务器，下次打开可继续读取。").setPositiveButton("知道了",null).show();
        });
        settingRow("立即同步","更新 Agents 与会话",R.drawable.ic_refresh,()->{session.refresh();Toast.makeText(this,"正在同步",Toast.LENGTH_SHORT).show();});
        sectionGap();TextView about=text("Leon for Android · "+versionName(),12,MUTED);about.setGravity(Gravity.CENTER);about.setPadding(dp(20),dp(24),dp(20),dp(24));homeRows.addView(about);
    }
    private View settingRow(String title,String summary,int iconId,Runnable action){
        LinearLayout item=row();item.setGravity(Gravity.CENTER_VERTICAL);item.setPadding(dp(18),dp(16),dp(16),dp(16));item.setBackground(ui.ripple(Color.WHITE,0));item.setFocusable(true);item.setOnClickListener(view->action.run());
        ImageView icon=new ImageView(this);icon.setImageResource(iconId);icon.setImageTintList(ColorStateList.valueOf(0xFF606060));item.addView(icon,new LinearLayout.LayoutParams(dp(23),dp(23)));
        LinearLayout labels=column();labels.addView(text(title,16,INK));if(!summary.isEmpty()){TextView subtitle=text(summary,12,MUTED);subtitle.setSingleLine();subtitle.setEllipsize(TextUtils.TruncateAt.END);LinearLayout.LayoutParams sp=new LinearLayout.LayoutParams(-1,-2);sp.topMargin=dp(6);labels.addView(subtitle,sp);}
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(0,-2,1);lp.leftMargin=dp(13);item.addView(labels,lp);
        ImageView arrow=new ImageView(this);arrow.setImageResource(R.drawable.ic_chevron);arrow.setImageTintList(ColorStateList.valueOf(0xFFBBBBBB));item.addView(arrow,new LinearLayout.LayoutParams(dp(18),dp(18)));
        homeRows.addView(item);homeRows.addView(ui.divider(54));return item;
    }
    private void sectionGap(){View space=new View(this);space.setBackgroundColor(ChatUi.BAR);homeRows.addView(space,new LinearLayout.LayoutParams(-1,dp(10)));}
    private String versionName(){try{return getPackageManager().getPackageInfo(getPackageName(),0).versionName;}catch(Exception ignored){return "";}}
    private void showHomeMenu(){PopupMenu menu=new PopupMenu(this,homeAdd);menu.getMenu().add("立即同步").setOnMenuItemClickListener(item->{session.refresh();return true;});menu.getMenu().add("新建群聊").setOnMenuItemClickListener(item->{showNewGroup();return true;});menu.show();}
    private void openAgent(MessageApi.Agent agent){startAgentChat(agent);}
    private void openAgentDetails(String agentId){
        if(session.agents.stream().noneMatch(agent->agent.id.equals(agentId))){Toast.makeText(this,"Agent 已不存在",Toast.LENGTH_SHORT).show();return;}
        hideKeyboard();composer.clearFocus();navigation.agent(agentId);agentDetailConnection=session.connectionStamp();agentDetailSignature="";showScreen();session.refresh();
    }
    private void startAgentChat(MessageApi.Agent agent){navigation.chat();session.openDirect(agent);showScreen();}
    private void openGroup(MessageApi.Conversation room){if(!room.kind.equals("direct"))navigation.agentId="";navigation.chat();session.select(room.id);showScreen();}

    private void buildAgentDetail(){
        LinearLayout bar=row();bar.setGravity(Gravity.CENTER_VERTICAL);bar.setPadding(dp(4),0,dp(4),0);
        ImageButton back=ui.icon(R.drawable.ic_back,"返回聊天");back.setId(R.id.agent_detail_back);back.setOnClickListener(view->onBackPressed());bar.addView(back);
        TextView title=text("Agent 详情",16,INK);title.setGravity(Gravity.CENTER);bar.addView(title,new LinearLayout.LayoutParams(0,dp(48),1));
        ImageButton refresh=ui.icon(R.drawable.ic_refresh,"刷新 Agent 详情");refresh.setOnClickListener(view->session.refresh());bar.addView(refresh);agentDetailScreen.addView(bar);agentDetailScreen.addView(ui.divider(0));
        ScrollView contents=new ScrollView(this);contents.setFillViewport(true);agentDetailRows=column();agentDetailRows.setPadding(dp(12),dp(12),dp(12),dp(16));contents.addView(agentDetailRows);agentDetailScreen.addView(contents,new LinearLayout.LayoutParams(-1,0,1));
    }
    private void renderAgentDetail(){
        MessageApi.Agent selected=null;for(var item:session.agents)if(item.id.equals(navigation.agentId)){selected=item;break;}
        if(selected==null){agentDetailRows.removeAllViews();agentDetailRows.addView(text("Agent 已不存在，请返回列表刷新。",15,MUTED));agentDetailSignature="";return;}
        final MessageApi.Agent agent=selected;var rooms=session.agentConversations(agent.id);
        StringBuilder signature=new StringBuilder(agent.id).append(agent.name).append(agent.handle).append(agent.description).append(agent.provider).append(agent.model).append(agent.enabled).append(agent.avatarId);
        for(var room:rooms)signature.append(room.id).append(room.name);
        if(signature.toString().equals(agentDetailSignature))return;agentDetailSignature=signature.toString();agentDetailRows.removeAllViews();
        LinearLayout profile=column();profile.setPadding(dp(16),dp(14),dp(16),dp(14));profile.setBackground(shape(Color.WHITE,14));
        LinearLayout identity=row();identity.setGravity(Gravity.CENTER_VERTICAL);identity.addView(avatar(agent.avatarId,48),new LinearLayout.LayoutParams(dp(48),dp(48)));
        LinearLayout names=column();names.setPadding(dp(12),0,dp(8),0);TextView name=text(agent.name,20,INK);name.setId(R.id.agent_detail_name);name.setTypeface(null,Typeface.BOLD);names.addView(name);
        TextView handle=text("@"+agent.handle+(agent.enabled?"":" · 已停用"),12,MUTED);handle.setPadding(0,dp(4),0,0);names.addView(handle);identity.addView(names,new LinearLayout.LayoutParams(0,-2,1));
        Button chat=action(rooms.isEmpty()?"开始聊天":"继续聊天");chat.setId(R.id.agent_detail_chat);chat.setTextColor(Color.WHITE);chat.setBackground(ui.ripple(GREEN,12));chat.setStateListAnimator(null);chat.setEnabled(agent.enabled);chat.setAlpha(agent.enabled?1f:.45f);chat.setOnClickListener(view->startAgentChat(agent));
        chat.setTextSize(13);chat.setPadding(dp(8),0,dp(8),0);chat.setMinimumHeight(dp(48));identity.addView(chat,new LinearLayout.LayoutParams(dp(80),-2));profile.addView(identity);
        LinearLayout introRow=row();introRow.setGravity(Gravity.TOP);introRow.setPadding(0,dp(14),0,0);TextView introTitle=text("介绍",12,MUTED);introTitle.setPadding(0,dp(2),0,0);introRow.addView(introTitle,new LinearLayout.LayoutParams(dp(40),-2));
        TextView intro=text(agent.description.isBlank()?"暂无介绍":agent.description,14,INK);intro.setId(R.id.agent_detail_description);intro.setLineSpacing(dp(3),1);introRow.addView(intro,new LinearLayout.LayoutParams(0,-2,1));profile.addView(introRow);
        LinearLayout modelRow=row();modelRow.setGravity(Gravity.TOP);modelRow.setPadding(0,dp(10),0,0);TextView modelTitle=text("模型",12,MUTED);modelTitle.setPadding(0,dp(2),0,0);modelRow.addView(modelTitle,new LinearLayout.LayoutParams(dp(40),-2));
        TextView model=text(agent.provider+" · "+(agent.model.isBlank()?"未提供模型信息":agent.model),14,INK);model.setId(R.id.agent_detail_model);model.setTextIsSelectable(true);modelRow.addView(model,new LinearLayout.LayoutParams(0,-2,1));profile.addView(modelRow);agentDetailRows.addView(profile);
        LinearLayout heading=row();heading.setGravity(Gravity.CENTER_VERTICAL);heading.setPadding(dp(2),dp(10),0,dp(4));TextView history=text("历史对话 · "+rooms.size(),16,INK);history.setTypeface(null,Typeface.BOLD);heading.addView(history,new LinearLayout.LayoutParams(0,-2,1));
        Button create=action("＋ 新建对话");create.setId(R.id.agent_detail_new);create.setEnabled(agent.enabled);create.setOnClickListener(view->tools.newConversation(agent));heading.addView(create);agentDetailRows.addView(heading);
        if(rooms.isEmpty()){TextView empty=text("暂无历史对话，开始聊聊吧。",14,MUTED);empty.setPadding(dp(4),dp(24),dp(4),dp(24));agentDetailRows.addView(empty);}
        for(var room:rooms){
            LinearLayout item=row();item.setGravity(Gravity.CENTER_VERTICAL);item.setPadding(dp(14),dp(16),dp(14),dp(16));item.setBackground(ui.ripple(Color.WHITE,14));item.setFocusable(true);item.setTag("agent-history:"+room.id);item.setContentDescription("打开对话："+room.name);item.setOnClickListener(view->openGroup(room));
            ImageView icon=new ImageView(this);icon.setImageResource(R.drawable.ic_threads);icon.setImageTintList(ColorStateList.valueOf(GREEN));item.addView(icon,new LinearLayout.LayoutParams(dp(24),dp(24)));
            TextView roomName=text(room.name,15,INK);roomName.setPadding(dp(12),0,dp(8),0);item.addView(roomName,new LinearLayout.LayoutParams(0,-2,1));ImageView arrow=new ImageView(this);arrow.setImageResource(R.drawable.ic_chevron);item.addView(arrow,new LinearLayout.LayoutParams(dp(18),dp(18)));
            LinearLayout.LayoutParams rp=new LinearLayout.LayoutParams(-1,-2);rp.bottomMargin=dp(8);agentDetailRows.addView(item,rp);
        }
    }

    private void buildChat(){
        LinearLayout bar=row();bar.setGravity(Gravity.CENTER_VERTICAL);bar.setPadding(dp(4),0,dp(4),0);bar.setBackgroundColor(ChatUi.BAR);
        ImageButton back=ui.icon(R.drawable.ic_back,"返回列表");back.setId(R.id.chat_back);back.setOnClickListener(view->onBackPressed());bar.addView(back);
        roomTitle=text("聊天",16,INK);roomTitle.setId(R.id.chat_title);roomTitle.setSingleLine();roomTitle.setHorizontallyScrolling(false);roomTitle.setEllipsize(TextUtils.TruncateAt.END);roomTitle.setGravity(Gravity.CENTER);
        bar.addView(roomTitle,new LinearLayout.LayoutParams(0,dp(48),1));ImageButton more=ui.icon(R.drawable.ic_more,"聊天更多操作");more.setId(R.id.chat_more);more.setOnClickListener(view->showChatMenu(more));bar.addView(more);chatScreen.addView(bar);chatScreen.addView(ui.divider(0));
        roomStatus=text("",11,MUTED);roomStatus.setSingleLine();roomStatus.setHorizontallyScrolling(false);roomStatus.setEllipsize(TextUtils.TruncateAt.END);roomStatus.setGravity(Gravity.CENTER);roomStatus.setPadding(dp(12),dp(6),dp(12),dp(6));chatScreen.addView(roomStatus);
        scroll=new ScrollView(this);scroll.setFillViewport(true);scroll.setOnScrollChangeListener((view,x,y,oldX,oldY)->session.refreshImages());
        timeline=column();timeline.setPadding(dp(12),dp(12),dp(12),dp(18));scroll.addView(timeline);chatScreen.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout inputArea=column();inputArea.setBackgroundColor(ChatUi.BAR);inputArea.addView(ui.divider(0));
        mentionPanel=column();mentionPanel.setPadding(dp(10),dp(6),dp(10),dp(6));mentionPanel.setBackgroundColor(Color.WHITE);mentionPanel.setVisibility(View.GONE);
        TextView mentionTitle=text("提及 Agent",12,MUTED);mentionTitle.setPadding(dp(6),dp(5),dp(6),dp(5));mentionPanel.addView(mentionTitle);
        ScrollView mentionScroll=new ScrollView(this);mentionRows=column();mentionScroll.addView(mentionRows);mentionPanel.addView(mentionScroll,new LinearLayout.LayoutParams(-1,dp(132)));inputArea.addView(mentionPanel);
        HorizontalScrollView attachmentScroll=new HorizontalScrollView(this);attachmentScroll.setHorizontalScrollBarEnabled(false);attachmentRows=row();attachmentRows.setPadding(dp(12),dp(6),dp(12),0);attachmentScroll.addView(attachmentRows);inputArea.addView(attachmentScroll);
        LinearLayout input=row();input.setGravity(Gravity.BOTTOM);input.setPadding(dp(10),dp(8),dp(8),dp(8));
        composer=new MentionEditText(this);composer.setId(R.id.chat_input);composer.setTextColor(INK);composer.setTextSize(16);composer.setHint("发送消息");composer.setHintTextColor(0xFFAAAAAA);
        composer.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_FLAG_MULTI_LINE|InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);composer.setMinLines(1);composer.setMaxLines(4);composer.setGravity(Gravity.TOP);
        composer.setPadding(dp(11),dp(10),dp(11),dp(10));composer.setBackground(shape(Color.WHITE,5));composer.setImeOptions(EditorInfo.IME_ACTION_SEND|EditorInfo.IME_FLAG_NO_EXTRACT_UI);composer.setText(session.draft);
        composer.imageInput=(uri,release)->session.addImage(uri,release);
        composer.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence value,int start,int count,int after){}public void afterTextChanged(Editable value){}
            public void onTextChanged(CharSequence value,int start,int before,int count){session.draft=value.toString();updateSend();composer.post(MainActivity.this::updateMentionSuggestions);}});
        composer.selectionChanged=this::updateMentionSuggestions;
        composer.setOnFocusChangeListener((view,focused)->{if(focused&&navigation.attachments){navigation.attachments=false;extras.setVisibility(View.GONE);chatAdd.setRotation(0);}updateMentionSuggestions();});
        composer.setOnEditorActionListener((view,action,event)->{if(action==EditorInfo.IME_ACTION_SEND&&!isComposing()){sendCurrent();return true;}return false;});
        composer.setOnKeyListener((view,key,event)->{
            if(event.getAction()!=KeyEvent.ACTION_DOWN||event.isCtrlPressed()||event.isAltPressed()||event.isMetaPressed()||event.isShiftPressed()||isComposing())return false;
            updateMentionSuggestions();if(mentionPanel.getVisibility()!=View.VISIBLE){if(key==KeyEvent.KEYCODE_ENTER){sendCurrent();return true;}return false;}
            if(key==KeyEvent.KEYCODE_ESCAPE){hideMentionSuggestions(true);return true;}if(mentionCandidates.isEmpty())return false;
            if(key==KeyEvent.KEYCODE_DPAD_DOWN||key==KeyEvent.KEYCODE_DPAD_UP){mentionIndex=(mentionIndex+(key==KeyEvent.KEYCODE_DPAD_DOWN?1:-1)+mentionCandidates.size())%mentionCandidates.size();highlightMention();return true;}
            if(key==KeyEvent.KEYCODE_ENTER||key==KeyEvent.KEYCODE_TAB){chooseMention(mentionIndex);return true;}return false;
        });
        input.addView(composer,new LinearLayout.LayoutParams(0,-2,1));
        chatAdd=ui.icon(R.drawable.ic_add,"附件与快捷命令");chatAdd.setId(R.id.chat_add);chatAdd.setOnClickListener(view->{hideKeyboard();composer.clearFocus();navigation.attachments=!navigation.attachments;showScreen();});
        input.addView(chatAdd,new LinearLayout.LayoutParams(dp(40),dp(40)));
        send=action("发送");send.setId(R.id.chat_send);send.setTextColor(Color.WHITE);send.setTypeface(null,Typeface.BOLD);send.setBackground(ui.ripple(GREEN,5));send.setOnClickListener(view->sendCurrent());
        LinearLayout.LayoutParams sp=new LinearLayout.LayoutParams(dp(58),dp(38));sp.leftMargin=dp(3);sp.bottomMargin=dp(1);input.addView(send,sp);inputArea.addView(input);
        extras=column();extras.setId(R.id.chat_extras);extras.setPadding(dp(12),dp(4),dp(12),dp(10));extras.setVisibility(View.GONE);
        LinearLayout first=row(),second=row();extras.addView(first);extras.addView(second);
        imageButton=attachmentAction(first,"相册",R.drawable.ic_photo,0xFF4778B2,0xFFEAF1FA,this::chooseImages);
        attachmentAction(first,"压缩上下文",R.drawable.ic_compact,0xFF35896A,0xFFE7F2EC,tools::compact).setTag("chat-tool:compact");
        attachmentAction(first,"查看上下文",R.drawable.ic_context,0xFF35896A,0xFFE7F2EC,tools::context).setTag("chat-tool:context");
        attachmentAction(first,"新建对话",R.drawable.ic_add,0xFF35896A,0xFFE7F2EC,tools::newConversation).setTag("chat-tool:new");
        attachmentAction(second,"加载备份",R.drawable.ic_restore,0xFF6979A4,0xFFECEDF6,tools::load).setTag("chat-tool:load");
        attachmentAction(second,"清理记录",R.drawable.ic_clear,0xFFB56360,0xFFF8ECEA,tools::clear).setTag("chat-tool:clear");
        mentionButton=attachmentAction(second,"@ Agent",R.drawable.ic_agents,0xFF35896A,0xFFE7F2EC,()->showAgents(true));inputArea.addView(extras);
        chatScreen.addView(inputArea);
    }
    private Button attachmentAction(LinearLayout parent,String label,int icon,int accent,int surface,Runnable action){
        Button button=ui.toolButton(label,icon,accent,surface);
        button.setOnClickListener(view->action.run());LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(0,-2,1);params.setMargins(dp(2),dp(2),dp(2),dp(2));
        button.setMinHeight(dp(88));parent.addView(button,params);return button;
    }
    private void chooseImages(){
        Intent picker=new Intent(Intent.ACTION_OPEN_DOCUMENT);picker.setType("image/*");picker.addCategory(Intent.CATEGORY_OPENABLE);picker.putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true);startActivityForResult(picker,42);
    }
    private void sendCurrent(){if(session.sendDraft(composer.getText().toString())){composer.setText("");navigation.attachments=false;extras.setVisibility(View.GONE);chatAdd.setRotation(0);scroll.post(()->scroll.fullScroll(View.FOCUS_DOWN));}}
    private void showChatMenu(View anchor){
        PopupMenu menu=new PopupMenu(this,anchor);menu.getMenu().add("会话信息").setOnMenuItemClickListener(item->{showConversationInfo();return true;});
        if(session.selected()!=null&&session.selected().kind.equals("group"))
            menu.getMenu().add("群成员").setOnMenuItemClickListener(item->{showGroupMembers();return true;});
        menu.getMenu().add("Token 用量").setOnMenuItemClickListener(item->{showUsage();return true;});
        menu.getMenu().add("快捷命令").setOnMenuItemClickListener(item->{hideKeyboard();composer.clearFocus();navigation.attachments=true;showScreen();return true;});
        menu.getMenu().add("新建对话").setOnMenuItemClickListener(item->{tools.newConversation();return true;});
        menu.getMenu().add("立即同步").setOnMenuItemClickListener(item->{session.refresh();return true;});
        if(session.selected()!=null&&!session.selected().kind.equals("direct"))menu.getMenu().add("提及 Agent").setOnMenuItemClickListener(item->{showAgents(true);return true;});menu.show();
    }
    private void showConversationInfo(){
        LinearLayout content=column();content.setPadding(dp(22),dp(12),dp(22),dp(12));content.addView(text(session.status,12,MUTED));
        for(var agent:session.availableAgents()){
            LinearLayout person=row();person.setGravity(Gravity.CENTER_VERTICAL);person.setPadding(0,dp(12),0,dp(8));person.addView(avatar(agent.avatarId,36));
            TextView name=text(agent.name+"  @"+agent.handle,14,INK);name.setPadding(dp(10),0,0,0);person.addView(name);content.addView(person);
        }
        ScrollView contents=new ScrollView(this);contents.addView(content);new AlertDialog.Builder(this).setTitle(session.title()).setView(contents).setPositiveButton("关闭",null).show();
    }
    private void showGroupMembers(){
        if(!session.configured())return;
        String room=session.selectedConversation;
        session.tool("正在读取群成员…",api->api.members(room,null),this::renderGroupMembers);
    }

    private void renderGroupMembers(List<MessageApi.User> users){
        if(isDestroyed()||isFinishing())return;
        String[] names=users.stream().map(MessageApi.User::username).toArray(String[]::new);
        var room=session.selected();
        var builder=new AlertDialog.Builder(this).setTitle("群成员").setItems(names,null).setNegativeButton("关闭",null);
        if(session.owns(room)&&!room.id.equals("shared")&&!room.id.startsWith("home:"))
            builder.setPositiveButton("添加用户",(dialog,which)->inviteUsers(room.id));
        builder.show();
    }

    private void inviteUsers(String roomId){
        LinearLayout form=column();
        form.setPadding(dp(24),dp(8),dp(24),0);
        EditText names=field(form,"已注册的 UserName（用逗号分隔）","",false);
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle("添加群成员").setView(form)
            .setNegativeButton("取消",null).setPositiveButton("添加",null).create();
        dialog.setOnShowListener(ignored->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{
            var invitees=usernames(names);
            if(invitees.isEmpty()){names.setError("请输入至少一个用户名");return;}
            if(invitees.size()>32){names.setError("每次最多添加 32 位用户");return;}
            if(!session.selectedConversation.equals(roomId))return;
            session.tool("正在添加群成员…",api->api.members(roomId,invitees),members->{
                dialog.dismiss();
                renderGroupMembers(members);
            });
        }));
        dialog.show();
    }

    private static List<String> usernames(EditText field){
        List<String> names=new ArrayList<>();
        for(String name:field.getText().toString().split("[,，]")){
            String trimmed=name.trim();
            if(!trimmed.isEmpty())names.add(trimmed);
        }
        return names;
    }

    private void hideKeyboard(){((InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(composer.getWindowToken(),0);}

    private void showUsage(){
        if(usageDialog!=null&&usageDialog.isShowing())return;
        usageSignature="";
        usageContent=column();usageContent.setPadding(dp(22),dp(12),dp(22),dp(12));
        ScrollView contents=new ScrollView(this);contents.addView(usageContent);
        usageDialog=new AlertDialog.Builder(this).setTitle("Token 用量").setView(contents)
            .setPositiveButton("关闭",null).setNeutralButton("刷新",null).create();
        usageDialog.setOnShowListener(dialog->{
            usageDialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(view->session.loadUsage());
            renderUsage();session.loadUsage();
        });
        usageDialog.show();
    }
    private static String usageNumber(long value){return java.text.NumberFormat.getIntegerInstance().format(value);}
    private void renderUsage(){
        if(usageDialog==null||!usageDialog.isShowing())return;
        String signature=session.configured()+":"+session.configuring+":"+session.usageBusy+":"+session.usageLoadedAt+":"+session.usageError;
        if(signature.equals(usageSignature))return;usageSignature=signature;
        usageContent.removeAllViews();
        usageContent.addView(text("当前用户触发的 Agent 回复、上下文压缩与归档用量。群聊用量计入发起者。",13,MUTED));
        usageDialog.getButton(AlertDialog.BUTTON_NEUTRAL).setEnabled(session.configured()&&!session.usageBusy&&!session.configuring);
        if(!session.configured()){usageContent.addView(text("请先在设置中连接服务",14,INK));return;}
        if(session.usageBusy)usageContent.addView(text("正在读取用量…",14,MUTED));
        if(!session.usageError.isEmpty())usageContent.addView(text(session.usageError,14,0xFFB3261E));
        if(session.usageLoadedAt!=0){
            long input=0,output=0,total=0,reported=0,unreported=0;
            for(var row:session.modelUsage){input+=row.inputTokens;output+=row.outputTokens;total+=row.totalTokens;reported+=row.reportedCalls;unreported+=row.unreportedCalls;}
            TextView sum=text("总 Token  "+usageNumber(total),22,INK);sum.setTypeface(null,Typeface.BOLD);sum.setPadding(0,dp(18),0,dp(8));usageContent.addView(sum);
            usageContent.addView(text("输入 "+usageNumber(input)+" · 输出 "+usageNumber(output),14,INK));
            usageContent.addView(text("已报告用量 "+usageNumber(reported)+" 次 · 未报告用量 "+usageNumber(unreported)+" 次",12,MUTED));
            double costLow=0,costHigh=0;int priced=0;
            for(var row:session.modelUsage){var cost=UsagePricing.estimate(row);if(cost!=null){costLow+=cost.low();costHigh+=cost.high();priced++;}}
            if(priced>0){TextView cost=text("已匹配模型估算  "+UsagePricing.label(new UsagePricing.Estimate(costLow,costHigh))+" USD",15,INK);cost.setPadding(0,dp(12),0,dp(4));cost.setTypeface(null,Typeface.BOLD);usageContent.addView(cost);}
            if(priced<session.modelUsage.size())usageContent.addView(text("部分模型暂无可匹配价格，未计入以上金额。",12,MUTED));
            if(session.modelUsage.isEmpty())usageContent.addView(text("暂无用量记录",14,MUTED));
            for(var row:session.modelUsage){
                TextView title=text(row.provider+" · "+row.model,15,INK);title.setTypeface(null,Typeface.BOLD);title.setPadding(0,dp(20),0,dp(6));usageContent.addView(title);
                TextView counts=text("总计 "+usageNumber(row.totalTokens)+" Token\n输入 "+usageNumber(row.inputTokens)+" · 输出 "+usageNumber(row.outputTokens),14,INK);counts.setTextIsSelectable(true);usageContent.addView(counts);
                usageContent.addView(text("已报告 "+usageNumber(row.reportedCalls)+" 次 · 未报告 "+usageNumber(row.unreportedCalls)+" 次",12,MUTED));
                var cost=UsagePricing.estimate(row);usageContent.addView(text(cost==null?"暂无可匹配价格":"估算 "+UsagePricing.label(cost)+" USD",14,INK));
            }
            TextView date=text("读取于 "+DateFormat.getDateTimeInstance().format(new Date(session.usageLoadedAt)),12,MUTED);date.setPadding(0,dp(18),0,0);usageContent.addView(date);
        }
        TextView note=text("按 2026-11-19 官网公开文本价格估算：输入分别按全部缓存命中 / 全部未命中计算；DeepSeek 分别使用非高峰 / 高峰价格。历史缓存命中、计费时段、价格变动和未报告调用无法还原，金额不是账单；可能不含长上下文、工具及其他费用。\n\nOpenAI：https://developers.openai.com/api/docs/pricing\nDeepSeek：https://api-docs.deepseek.com/quick_start/pricing/",12,MUTED);
        android.text.util.Linkify.addLinks(note,android.text.util.Linkify.WEB_URLS);
        note.setPadding(0,dp(16),0,dp(8));usageContent.addView(note);
    }

    @Override public void changed(){
        if(homeScreen==null)return;
        renderUsage();tools.changed();
        if(!session.configured()&&navigation.tab!=ChatNavigation.Tab.SETTINGS&&session.status.equals("登录已失效，请重新登录。")){
            composer.setText("");
            navigation.tab(ChatNavigation.Tab.SETTINGS);
            homeSignature="";
            showScreen();
            return;
        }
        if(settings!=null&&settings.isShowing())settings.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(!session.configuring);
        if(!navigation.agentId.isEmpty()&&agentDetailConnection!=session.connectionStamp()){navigation.tab(ChatNavigation.Tab.AGENTS);showScreen();return;}
        if(!navigation.agentId.isEmpty()){renderAgentDetail();return;}
        if(!navigation.inChat){renderHome();return;}
        roomTitle.setText(session.title());
        String subtitle=session.toolsBusy?session.toolsStatus:session.openingConversation()?"正在打开会话…":!session.connected?session.status:"";
        roomStatus.setText(subtitle);roomStatus.setVisibility(subtitle.isEmpty()?View.GONE:View.VISIBLE);
        boolean direct=session.selected()!=null&&session.selected().kind.equals("direct");mentionButton.setVisibility(direct?View.INVISIBLE:View.VISIBLE);mentionButton.setEnabled(!session.availableAgents().isEmpty());
        if(!composer.getText().toString().equals(session.draft)){composer.setText(session.draft);composer.setSelection(composer.length());}
        if(!renderedConversation.equals(session.selectedConversation)){renderedConversation=session.selectedConversation;hideMentionSuggestions(false);dismissedMentionKey="";mentionKey="";renderedRevision=-1;attachmentSignature="";timeline.setTag(null);RichMarkdownView.releaseTree(timeline);timeline.removeAllViews();}
        updateSend();renderAttachments();updateMentionSuggestions();
        if(renderedRevision!=session.revision){renderMessages();renderedRevision=session.revision;}
        if(older!=null){older.setText(session.loadingOlder?"正在加载…":"加载更早的消息");older.setEnabled(!session.loadingOlder);older.setVisibility(session.hasOlder?View.VISIBLE:View.GONE);}
    }
    private void updateSend(){
        if(send==null)return;int length=composer.getText().length();boolean hasContent=length>0||!session.draftImages.isEmpty()||session.preparingImages>0;
        send.setVisibility(hasContent?View.VISIBLE:View.GONE);send.setEnabled(session.canSend(composer.getText().toString()));send.setAlpha(send.isEnabled()?1f:.4f);
        composer.setError(length>8000?"消息最多 8,000 字符":null);
    }
    @Override public void error(String message){if(!isFinishing()&&!isDestroyed())new AlertDialog.Builder(this).setTitle("暂未完成").setMessage(message).setPositiveButton("知道了",null).show();}
    private void renderMessages(){
        int previousY=scroll.getScrollY(),previousHeight=timeline.getHeight();boolean nearBottom=timeline.getChildCount()==0||previousHeight-scroll.getHeight()-previousY<dp(100);
        Object firstTag=timeline.getTag();long firstId=session.messages.isEmpty()?0:session.messages.get(0).id;boolean prepended=firstTag instanceof Long&&firstId<(Long)firstTag;
        timeline.setTag(firstId);RichMarkdownView.releaseTree(timeline);timeline.removeAllViews();older=action("加载更早的消息");older.setTextColor(MUTED);older.setOnClickListener(view->session.older());older.setVisibility(session.hasOlder?View.VISIBLE:View.GONE);timeline.addView(older);
        if(session.messages.isEmpty()&&session.currentPending().isEmpty()){
            TextView empty=text(session.openingConversation()?"正在打开会话…":"开始和 "+session.title()+" 聊天",13,MUTED);empty.setGravity(Gravity.CENTER);empty.setPadding(dp(16),dp(45),dp(16),dp(35));timeline.addView(empty);
        }
        java.util.ArrayList<JSONObject> operations=new java.util.ArrayList<>();
        for(int i=0;i<session.contextOperations.length();i++){
            JSONObject operation=session.contextOperations.optJSONObject(i);if(operation!=null)operations.add(operation);
        }
        operations.sort(java.util.Comparator.comparingLong(operation->{long created=operation.optLong("createdAt",0);return created>0?created:Long.MAX_VALUE;}));
        java.util.ArrayList<MessageApi.Job> jobs=new java.util.ArrayList<>(session.visibleJobs());
        jobs.sort(java.util.Comparator.comparingLong(job->job.messageId));
        int operationIndex=0,jobIndex=0;long lastTime=0;
        for(MessageApi.Message message:session.messages){
            while(jobIndex<jobs.size()&&jobs.get(jobIndex).messageId<message.id)addJobNotice(jobs.get(jobIndex++));
            while(operationIndex<operations.size()&&operations.get(operationIndex).optLong("createdAt",0)>0&&operations.get(operationIndex).optLong("createdAt")<=message.createdAt){
                addContextNotice(operations.get(operationIndex++));
            }
            if(lastTime==0||Math.abs(message.createdAt-lastTime)>5*60*1000){addTime(message.createdAt);lastTime=message.createdAt;}
            addBubble(message.text,message.sender,"",session.mine(message),null,message.role.equals("assistant")?message.agentId:null,message.imageIds);
            while(jobIndex<jobs.size()&&jobs.get(jobIndex).messageId==message.id)addJobNotice(jobs.get(jobIndex++));
        }
        while(operationIndex<operations.size())addContextNotice(operations.get(operationIndex++));
        while(jobIndex<jobs.size())addJobNotice(jobs.get(jobIndex++));
        for(JSONObject message:session.currentPending()){
            boolean sending=session.sending.contains(message.optString("clientMessageId"));addBubble(message.optString("text"),message.optString("sender"),sending?"发送中…":"发送未完成",true,sending?null:message,null,ChatSession.imageIds(message));
        }
        if(session.dismissedFailureCount()>0){
            Button restore=action("恢复已忽略的失败提示（"+session.dismissedFailureCount()+"）");restore.setTextSize(12);restore.setTextColor(MUTED);
            restore.setTag("restore-dismissed-jobs");restore.setOnClickListener(view->session.restoreDismissedJobs());timeline.addView(restore);
        }
        scroll.post(()->{if(prepended)scroll.scrollTo(0,previousY+timeline.getHeight()-previousHeight);else if(nearBottom)scroll.fullScroll(View.FOCUS_DOWN);else scroll.scrollTo(0,previousY);session.refreshImages();});
    }
    private void addJobNotice(MessageApi.Job job){
            LinearLayout notice=row();notice.setGravity(Gravity.CENTER_VERTICAL);notice.setPadding(dp(12),dp(3),dp(6),dp(3));notice.setBackground(shape(0xFFE4E4E4,6));
            TextView info=text(job.agentName+" · "+(job.status.equals("FAILED")?job.error:job.status.equals("RUNNING")?"正在回复…":"等待回复…"),12,0xFF777777);info.setMaxLines(3);notice.addView(info,new LinearLayout.LayoutParams(0,-2,1));
            if(job.status.equals("FAILED")){
                if(session.user==null||session.user.id().equals(job.userId)){
                    Button retry=action("重试");retry.setOnClickListener(view->session.retryJob(job));notice.addView(retry,new LinearLayout.LayoutParams(dp(54),dp(48)));
                }
                Button dismiss=action("×");dismiss.setTextSize(20);dismiss.setTextColor(MUTED);
                dismiss.setContentDescription("忽略 "+job.agentName+" 的失败提示");dismiss.setTag("dismiss-job:"+job.messageId+":"+job.agentId);
                dismiss.setOnClickListener(view->session.dismissJob(job));notice.addView(dismiss,new LinearLayout.LayoutParams(dp(48),dp(48)));
            }
            LinearLayout.LayoutParams np=new LinearLayout.LayoutParams(-1,-2);np.topMargin=dp(7);np.bottomMargin=dp(7);timeline.addView(notice,np);
    }
    private void addContextNotice(JSONObject operation){
        String status=operation.optString("status"),detail=status.equals("FAILED")?operation.optString("error"):status.equals("SUCCEEDED")?operation.optString("result"):"上下文压缩中…";
        TextView notice=text(operation.optString("agentName")+" · "+detail,12,MUTED);notice.setPadding(dp(12),dp(10),dp(12),dp(10));timeline.addView(notice);
    }
    private void addTime(long timestamp){
        String value=android.text.format.DateUtils.isToday(timestamp)?DateFormat.getTimeInstance(DateFormat.SHORT).format(new Date(timestamp)):new SimpleDateFormat("M月d日 HH:mm",Locale.getDefault()).format(new Date(timestamp));
        TextView time=text(value,11,0xFFAAAAAA);time.setGravity(Gravity.CENTER);time.setPadding(0,dp(10),0,dp(17));timeline.addView(time);
    }
    private void addBubble(String body,String sender,String detail,boolean mine,JSONObject retry,String agentId,List<String> images){
        boolean wideAgentReply=!mine&&agentId!=null&&!agentId.isEmpty()&&body.codePointCount(0,body.length())>500;
        LinearLayout message=row();message.setGravity(Gravity.TOP);LinearLayout.LayoutParams mp=new LinearLayout.LayoutParams(-1,-2);mp.bottomMargin=dp(15);
        LinearLayout content=column();content.setGravity(mine?Gravity.END:Gravity.START);
        View identity;
        if(mine){TextView initials=text(sender.isEmpty()?"我":new String(Character.toChars(sender.codePointAt(0))),16,Color.WHITE);initials.setGravity(Gravity.CENTER);initials.setBackground(shape(0xFF719983,6));identity=initials;}
        else {
            identity=avatar(session.avatarFor(agentId),40);
            if(agentId!=null&&!agentId.isEmpty()){identity.setTag("message-agent-avatar:"+agentId);identity.setOnClickListener(view->openAgentDetails(agentId));identity.setContentDescription("查看 "+sender+" 的详情");}
        }
        if(wideAgentReply){
            message.setOrientation(LinearLayout.VERTICAL);
            LinearLayout header=row();header.setGravity(Gravity.CENTER_VERTICAL);header.addView(identity,new LinearLayout.LayoutParams(dp(40),dp(40)));
            TextView name=text(sender,11,MUTED);name.setPadding(dp(8),0,0,0);header.addView(name);message.addView(header);
            LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(-1,-2);cp.topMargin=dp(7);message.addView(content,cp);
        }
        else if(mine){message.addView(new View(this),new LinearLayout.LayoutParams(dp(44),1));message.addView(content,new LinearLayout.LayoutParams(0,-2,1));LinearLayout.LayoutParams av=new LinearLayout.LayoutParams(dp(40),dp(40));av.leftMargin=dp(7);message.addView(identity,av);}
        else{message.addView(identity,new LinearLayout.LayoutParams(dp(40),dp(40)));LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(0,-2,1);cp.leftMargin=dp(7);message.addView(content,cp);message.addView(new View(this),new LinearLayout.LayoutParams(dp(agentId!=null?4:44),1));}
        if(!mine&&!wideAgentReply&&session.selected()!=null&&!session.selected().kind.equals("direct")){TextView name=text(sender,11,MUTED);name.setPadding(dp(5),0,0,dp(5));content.addView(name);}
        for(String id:images){
            ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.FIT_CENTER);image.setPadding(dp(3),dp(3),dp(3),dp(3));image.setBackground(shape(Color.WHITE,6));
            int width=Math.min(dp(220),getResources().getDisplayMetrics().widthPixels-dp(125));LinearLayout.LayoutParams ip=new LinearLayout.LayoutParams(width,Math.round(width*.75f));ip.bottomMargin=dp(5);content.addView(image,ip);session.bindImage(image,id);
            image.setOnClickListener(view->{ImageView large=new ImageView(this);large.setScaleType(ImageView.ScaleType.FIT_CENTER);large.setAdjustViewBounds(true);session.bindImage(large,id,true);new AlertDialog.Builder(this).setTitle("图片预览").setView(large).setPositiveButton("关闭",null).show();});
        }
        if(!body.isEmpty()){
            if(RichMarkdownView.isRequired(body)){
                RichMarkdownView rich=new RichMarkdownView(this,body,mine);rich.setBackground(wideAgentReply?shape(Color.WHITE,5):ui.bubble(mine));content.addView(rich,new LinearLayout.LayoutParams(-1,-2));
            }else{
                TextView bubble=text("",14,INK);bubble.setPadding(dp(12),dp(10),dp(12),dp(10));bubble.setLineSpacing(dp(2),1);bubble.setBackground(wideAgentReply?shape(Color.WHITE,5):ui.bubble(mine));
                boolean table=markdown.setText(bubble,body,mine);
                bubble.setOnLongClickListener(view->{((ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("消息",body));Toast.makeText(this,"已复制",Toast.LENGTH_SHORT).show();return true;});
                content.addView(bubble,new LinearLayout.LayoutParams(wideAgentReply||table?-1:-2,-2));
            }
        }
        if(!detail.isEmpty()){TextView state=text(detail,10,MUTED);state.setPadding(dp(5),dp(4),dp(5),0);content.addView(state);}
        if(retry!=null){Button button=action("重试发送");button.setOnClickListener(view->session.retry(retry));content.addView(button);}
        timeline.addView(message,mp);
    }
    @Override protected void onActivityResult(int requestCode,int resultCode,Intent data){
        super.onActivityResult(requestCode,resultCode,data);if(tools.result(requestCode,resultCode,data))return;if(requestCode!=42||resultCode!=RESULT_OK||data==null)return;
        if(data.getClipData()!=null){var clip=data.getClipData();for(int i=0;i<Math.min(clip.getItemCount(),5);i++)session.addImage(clip.getItemAt(i).getUri(),()->{});}else if(data.getData()!=null)session.addImage(data.getData(),()->{});
    }
    private void renderAttachments(){
        imageButton.setEnabled(session.configured()&&!session.configuring&&session.draftImages.size()+session.preparingImages<4);imageButton.setText(session.preparingImages>0?"处理中…":"相册");
        String signature=session.selectedConversation+session.draftImages.stream().map(image->image.id).collect(java.util.stream.Collectors.joining());if(signature.equals(attachmentSignature))return;
        attachmentSignature=signature;attachmentRows.removeAllViews();attachmentRows.setVisibility(session.draftImages.isEmpty()?View.GONE:View.VISIBLE);
        for(ChatImage image:session.draftImages){
            FrameLayout item=new FrameLayout(this);ImageView preview=new ImageView(this);preview.setScaleType(ImageView.ScaleType.CENTER_CROP);preview.setBackground(shape(Color.WHITE,6));preview.setClipToOutline(true);
            var options=new android.graphics.BitmapFactory.Options();options.inSampleSize=8;preview.setImageBitmap(android.graphics.BitmapFactory.decodeByteArray(image.data,0,image.data.length,options));item.addView(preview,new FrameLayout.LayoutParams(dp(64),dp(64)));
            TextView remove=text("×",18,Color.WHITE);remove.setGravity(Gravity.CENTER);remove.setBackground(shape(0xAA000000,15));remove.setContentDescription("移除图片");remove.setOnClickListener(view->session.removeImage(image.id));
            FrameLayout.LayoutParams rp=new FrameLayout.LayoutParams(dp(30),dp(30),Gravity.TOP|Gravity.END);item.addView(remove,rp);LinearLayout.LayoutParams ip=new LinearLayout.LayoutParams(dp(72),dp(68));ip.rightMargin=dp(6);attachmentRows.addView(item,ip);
        }
    }
    private boolean isComposing(){return android.view.inputmethod.BaseInputConnection.getComposingSpanStart(composer.getText())>=0;}
    private void hideMentionSuggestions(boolean dismiss){
        if(dismiss)dismissedMentionKey=mentionKey;
        if(mentionPanel!=null)mentionPanel.setVisibility(View.GONE);
        boolean direct=session.selected()!=null&&session.selected().kind.equals("direct");
        if(mentionButton!=null)mentionButton.setVisibility(direct?View.INVISIBLE:View.VISIBLE);
    }
    private void updateMentionSuggestions(){
        if(composer==null||mentionPanel==null)return;
        MentionCompletion.Token token=composer.hasFocus()&&!isComposing()?MentionCompletion.token(composer.getText().toString(),composer.getSelectionStart(),composer.getSelectionEnd()):null;
        String key=token==null?"":session.selectedConversation+":"+token.signature()+":"+composer.getSelectionStart();
        if(token==null||session.selected()==null||!session.selected().kind.equals("group")||key.equals(dismissedMentionKey)){
            hideMentionSuggestions(false);if(key.isEmpty()){dismissedMentionKey="";mentionKey="";mentionRenderKey="";}return;
        }
        java.util.List<MessageApi.Agent> filtered=new java.util.ArrayList<>();
        for(MessageApi.Agent agent:session.availableAgents())if(MentionCompletion.matches(agent.name,agent.handle,token.query)&&filtered.size()<8)filtered.add(agent);
        if(!key.equals(mentionKey))mentionIndex=0;mentionKey=key;
        StringBuilder signature=new StringBuilder(key);for(MessageApi.Agent agent:filtered)signature.append(agent.id).append(agent.name).append(agent.avatarId);
        if(!signature.toString().equals(mentionRenderKey)){
            mentionRenderKey=signature.toString();mentionCandidates.clear();mentionCandidates.addAll(filtered);mentionRows.removeAllViews();
            if(filtered.isEmpty()){TextView empty=text("没有匹配的 Agent",12,MUTED);empty.setPadding(dp(9),dp(10),dp(9),dp(10));mentionRows.addView(empty);}
            for(int index=0;index<filtered.size();index++){
                MessageApi.Agent agent=filtered.get(index);final int chosen=index;
                LinearLayout option=row();option.setGravity(Gravity.CENTER_VERTICAL);option.setPadding(dp(8),dp(6),dp(8),dp(6));option.setFocusable(false);option.setContentDescription(agent.name+" @"+agent.handle);
                option.addView(avatar(agent.avatarId,30));LinearLayout identity=column();identity.setPadding(dp(9),0,0,0);identity.addView(text(agent.name,13,INK));identity.addView(text("@"+agent.handle,10,MUTED));option.addView(identity);
                option.setOnClickListener(v->chooseMention(chosen));mentionRows.addView(option);
            }
        }
        if(mentionIndex>=mentionCandidates.size())mentionIndex=0;
        mentionPanel.setVisibility(View.VISIBLE);highlightMention();
    }
    private void highlightMention(){
        for(int i=0;i<mentionRows.getChildCount();i++)mentionRows.getChildAt(i).setBackground(shape(i==mentionIndex&&!mentionCandidates.isEmpty()?0xFFE2F4E9:Color.TRANSPARENT,8));
        if(!mentionCandidates.isEmpty())mentionRows.getChildAt(mentionIndex).requestRectangleOnScreen(new android.graphics.Rect(0,0,mentionRows.getChildAt(mentionIndex).getWidth(),mentionRows.getChildAt(mentionIndex).getHeight()),true);
    }
    private void chooseMention(int index){
        if(index<0||index>=mentionCandidates.size()||isComposing())return;
        String text=composer.getText().toString();var token=MentionCompletion.token(text,composer.getSelectionStart(),composer.getSelectionEnd());
        MessageApi.Agent agent=mentionCandidates.get(index);boolean eligible=false;for(var available:session.availableAgents())if(available.id.equals(agent.id))eligible=true;
        if(token==null||!eligible||!MentionCompletion.matches(agent.name,agent.handle,token.query))return;
        String insert=MentionCompletion.insertion(text,token,agent.handle);int caret=MentionCompletion.caretAfterInsertion(text,token,insert);composer.getText().replace(token.start,token.end,insert);composer.setSelection(caret);composer.requestFocus();
        hideMentionSuggestions(false);mentionKey="";dismissedMentionKey="";
    }

    private void showAgents(boolean mention) {
        java.util.List<MessageApi.Agent> directory=new java.util.ArrayList<>();
        for(MessageApi.Agent agent:mention?session.availableAgents():session.agents)if(agent.enabled)directory.add(agent);
        if(directory.isEmpty()){Toast.makeText(this,"请先在服务端页面配置并启用 Agent",Toast.LENGTH_LONG).show();return;}
        String[] labels=new String[directory.size()];for(int i=0;i<labels.length;i++)labels[i]=directory.get(i).name+"  @"+directory.get(i).handle;
        ArrayAdapter<MessageApi.Agent> adapter=new ArrayAdapter<MessageApi.Agent>(this,android.R.layout.simple_list_item_1,directory){
            @Override public View getView(int position,View recycled,android.view.ViewGroup parent){
                MessageApi.Agent agent=getItem(position);LinearLayout item=row();item.setGravity(Gravity.CENTER_VERTICAL);item.setPadding(dp(18),dp(10),dp(18),dp(10));
                item.addView(avatar(agent.avatarId,40));LinearLayout identity=column();identity.setPadding(dp(12),0,0,0);identity.addView(text(agent.name,15,INK));identity.addView(text("@"+agent.handle,11,MUTED));item.addView(identity);return item;
            }
        };
        new AlertDialog.Builder(this).setTitle(mention?"@哪位 Agent":"与 Agent 私聊").setAdapter(adapter,(d,index)->{if(mention)session.mention(directory.get(index));else openAgent(directory.get(index));}).setNegativeButton("取消",null).show();
    }
    private void showNewGroup() {
        if(!session.configured())return;
        LinearLayout form=column();form.setPadding(dp(24),dp(8),dp(24),0);
        EditText name=field(form,"群名称","",false);
        EditText members=field(form,"群成员 UserName（用逗号分隔，可选）","",false);
        form.addView(text("选择加入群聊的 Agent（最多 32 个）",12,MUTED));
        java.util.List<CheckBox> boxes=new java.util.ArrayList<>();java.util.List<MessageApi.Agent> directory=new java.util.ArrayList<>();
        for(MessageApi.Agent agent:session.agents)if(agent.enabled){CheckBox box=new CheckBox(this);box.setText(String.format(java.util.Locale.getDefault(),"%s @%s",agent.name,agent.handle));form.addView(box);boxes.add(box);directory.add(agent);}
        ScrollView contents=new ScrollView(this);contents.addView(form);
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle("新建群聊").setView(contents).setNegativeButton("取消",null).setPositiveButton("创建",null).create();
        dialog.setOnShowListener(d->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{
            String title=name.getText().toString().trim();if(title.isEmpty()||title.length()>60){name.setError("名称应为 1–60 字");return;}
            java.util.List<String> ids=new java.util.ArrayList<>();for(int i=0;i<boxes.size();i++)if(boxes.get(i).isChecked())ids.add(directory.get(i).id);
            if(ids.size()>32){Toast.makeText(this,"最多选择 32 个 Agent",Toast.LENGTH_SHORT).show();return;}
            List<String> invitees=usernames(members);
            if(invitees.size()>32){members.setError("每次最多添加 32 位用户");return;}
            session.createGroup(title,ids,invitees,room->{
                if(!navigation.inChat&&navigation.tab==ChatNavigation.Tab.GROUPS)openGroup(room);
                else Toast.makeText(this,"群聊已创建",Toast.LENGTH_SHORT).show();
            });dialog.dismiss();
        }));dialog.show();
    }

    private void confirmLogout(){
        new AlertDialog.Builder(this).setTitle("退出当前账号？").setMessage("下次登录请重新输入服务访问令牌。")
            .setNegativeButton("取消",null).setPositiveButton("退出登录",(dialog,which)->session.logout()).show();
    }

    private void showSettings(){
        if(settings!=null&&settings.isShowing())return;
        if(session.configured()){confirmLogout();return;}
        LinearLayout form=column();
        form.setPadding(dp(24),dp(8),dp(24),dp(12));
        EditText name=field(form,"UserName",session.sender.equals(android.os.Build.MODEL)?"":session.sender,false);
        EditText address=field(form,"服务地址",session.server,false);
        address.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_URI);
        boolean hasLegacyToken=!session.legacyServiceToken(session.server).isEmpty();
        EditText token=field(form,hasLegacyToken?"服务访问令牌（留空沿用已保存的令牌）":"服务访问令牌","",true);
        TextView note=text("新用户名会自动注册。App 会记住当前登录状态。",13,MUTED);
        note.setPadding(0,dp(12),0,0);
        form.addView(note);
        ScrollView scroll=new ScrollView(this);
        scroll.addView(form);
        settings=new AlertDialog.Builder(this).setTitle("注册或登录").setView(scroll)
            .setNegativeButton("取消",null).setPositiveButton("继续",null).create();
        settings.setOnShowListener(ignored->settings.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->
            session.login(address.getText().toString(),token.getText().toString(),name.getText().toString(),()->{
                if(isDestroyed())return;
                settings.dismiss();
                navigation.tab(ChatNavigation.Tab.AGENTS);
                homeSignature="";
                showScreen();
            })));
        settings.show();
        settings.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(!session.configuring);
    }

    private EditText field(LinearLayout form, String label, String value, boolean secret) {
        TextView title = text(label, 12, MUTED); title.setPadding(0, dp(18), 0, dp(4)); form.addView(title);
        EditText edit = new EditText(this); edit.setSingleLine(true); edit.setTextSize(15);
        edit.setInputType(android.text.InputType.TYPE_CLASS_TEXT | (secret ? android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD : android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES));
        if (secret) { edit.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO); edit.setSaveEnabled(false); }
        edit.setText(value); form.addView(edit, new LinearLayout.LayoutParams(-1, -2)); return edit;
    }
    private ImageView avatar(String avatarId,int size){
        ImageView image=new ImageView(this);image.setLayoutParams(new LinearLayout.LayoutParams(dp(size),dp(size)));image.setScaleType(ImageView.ScaleType.FIT_CENTER);
        image.setPadding(dp(2),dp(2),dp(2),dp(2));image.setBackground(shape(0xFFE1F0E8,7));image.setClipToOutline(true);image.setContentDescription("Agent 头像");session.bindAvatar(image,avatarId);return image;
    }
    private LinearLayout column(){LinearLayout view=new LinearLayout(this);view.setOrientation(LinearLayout.VERTICAL);return view;}
    private LinearLayout row(){LinearLayout view=new LinearLayout(this);view.setOrientation(LinearLayout.HORIZONTAL);return view;}
    private TextView text(String value,int size,int color){return ui.text(value,size,color);}
    private Button action(String label){return ui.button(label);}
    private GradientDrawable shape(int color,int radius){return ui.shape(color,radius);}
    private int dp(float value){return ui.dp(value);}
}
