package com.leon.app;

import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.*;
import android.graphics.Color;
import android.widget.*;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

/** Local inbox notifications plus the optional vivo remote transport. Never polls after the Activity stops. */
final class ChatNotifications {
    static final int PERMISSION=83;static final String CHANNEL="chat_messages";
    private final Activity activity;private final ChatSession session;private final java.util.function.Consumer<String> openRoom;
    private final Handler main=new Handler(Looper.getMainLooper());private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final android.content.SharedPreferences preferences;
    private boolean running,busy;private int epoch,connection=-1;private Long after;private String visibleRoom,status="通知尚未开启";private final Set<Long> displayed=new HashSet<>();private Future<?> request;
    ChatNotifications(Activity activity,ChatSession session,java.util.function.Consumer<String> openRoom){this.activity=activity;this.session=session;this.openRoom=openRoom;preferences=activity.getSharedPreferences("notifications",Context.MODE_PRIVATE);channel(activity);}
    private boolean allowed(){return Build.VERSION.SDK_INT<33||activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED;}
    boolean enabled(){return preferences.getBoolean("enabled",false);}
    String status(){return status;}
    void start(){running=true;VivoPushBridge.enable(activity);tick();}
    void stop(){running=false;epoch++;busy=false;if(request!=null)request.cancel(true);main.removeCallbacksAndMessages(null);preferences.edit().remove("visibleRoom").apply();registerBackground();}
    void close(){stop();worker.shutdownNow();}
    void changed(String room){visibleRoom=room;preferences.edit().putString("visibleRoom",room==null?"":room).putLong("visibleUntil",System.currentTimeMillis()+15000).apply();
        if(connection!=session.connectionStamp()){connection=session.connectionStamp();after=null;displayed.clear();epoch++;busy=false;activity.getSystemService(NotificationManager.class).cancelAll();if(!session.configured()){status="请先登录服务器";preferences.edit().remove("account").apply();VivoPushBridge.disable(activity);}else{preferences.edit().putString("account",session.user.id()).apply();VivoPushBridge.enable(activity);tick();}}
    }
    private void tick(){
        main.removeCallbacks(next);if(!running||busy||!enabled()||!allowed()||!session.configured()||worker.isShutdown())return;
        MessageApi api=session.searchClient();int stamp=epoch,accountConnection=session.connectionStamp();String account=session.user.id(),device=session.deviceId,currentRoom=visibleRoom;Long cursor=after;boolean previews=preferences.getBoolean("previews",false);busy=true;
        request=worker.submit(()->{
            try{
                JSONObject server=api.notificationStatus();String token=account.equals(preferences.getString("vivoBoundAccount",""))?preferences.getString("vivoToken",""):"";boolean remote=BuildConfig.VIVO_PUSH_CONFIGURED&&!token.isEmpty()&&server.optBoolean("vivo");
                api.registerNotifications(registration(device,currentRoom,token,previews));var page=api.notifications(device,cursor,previews);
                main.post(()->{if(stamp!=epoch||accountConnection!=session.connectionStamp())return;busy=false;
                    status=remote?"消息通知已开启；vivo 通道已注册":"应用运行时通知已开启；vivo 后台推送待配置";
                    JSONArray events=page.optJSONArray("events");if(events!=null)for(int i=0;i<events.length();i++){JSONObject event=events.optJSONObject(i);if(event==null)continue;long id=event.optLong("id");String room=event.optString("room");
                        if(!room.equals(visibleRoom)&&displayed.add(id))notify(activity,account,room,id,event.optString("title","Leon"),event.optString("text","收到一条新消息"));}
                    if(displayed.size()>1000)displayed.clear();after=page.optLong("nextAfter",cursor==null?0:cursor);
                    main.postDelayed(next,page.optBoolean("hasMore")?0:8000);
                });
            }catch(Exception e){main.post(()->{if(stamp!=epoch||accountConnection!=session.connectionStamp())return;busy=false;session.searchFailure(e);status=e.getMessage()==null?"通知同步未完成，请稍后重试。":e.getMessage();main.postDelayed(next,15000);});}
        });
    }
    private final Runnable next=this::tick;
    private JSONObject registration(String device,String room,String token,boolean previews)throws JSONException{
        return new JSONObject().put("deviceId",device).put("platform","android").put("provider",BuildConfig.VIVO_PUSH_CONFIGURED&&!token.isEmpty()?"vivo":"local").put("token",token).put("environment","production").put("enabled",enabled()).put("preview",previews).put("activeRoom",room==null?JSONObject.NULL:room);
    }
    private void registerBackground(){
        MessageApi api=session.searchClient();if(api==null||worker.isShutdown()||!enabled())return;
        try {JSONObject registration=registration(session.deviceId,null,session.user!=null&&session.user.id().equals(preferences.getString("vivoBoundAccount",""))?preferences.getString("vivoToken",""):"",preferences.getBoolean("previews",false));worker.execute(()->{try{api.registerNotifications(registration);}catch(Exception ignored){}});}catch(Exception ignored){}
    }
    void showSettings(){
        LinearLayout rows=new LinearLayout(activity);rows.setOrientation(LinearLayout.VERTICAL);rows.setPadding(36,12,36,8);
        Switch enable=new Switch(activity);enable.setText("新消息通知");enable.setTextColor(Color.BLACK);enable.setChecked(enabled());rows.addView(enable);
        Switch preview=new Switch(activity);preview.setText("通知显示消息预览");preview.setTextColor(Color.BLACK);preview.setChecked(preferences.getBoolean("previews",false));rows.addView(preview);
        TextView detail=new TextView(activity);detail.setTextColor(Color.BLACK);detail.setText(status+"\n\n未配置 vivo 应用时，仅在应用运行期间提醒。开启 vivo 推送将使用 vivo 官方 SDK，用于设备注册与消息送达。");detail.setPadding(0,20,0,12);rows.addView(detail);
        TextView privacy=new TextView(activity);privacy.setText("vivo 推送 SDK 隐私说明");privacy.setTextColor(Color.BLACK);privacy.setPadding(0,12,0,12);privacy.setOnClickListener(v->activity.startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse("https://developers.vivo.com/doc/d/23807c559e844cbeb06049ee69e71833"))));rows.addView(privacy);
        enable.setOnCheckedChangeListener((v,value)->{if(value&&!allowed()){enable.setChecked(false);activity.requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS},PERMISSION);return;}setEnabled(value);detail.setText(status);});
        preview.setOnCheckedChangeListener((v,value)->{preferences.edit().putBoolean("previews",value).apply();epoch++;busy=false;tick();});
        new AlertDialog.Builder(activity).setTitle("消息通知").setView(rows).setPositiveButton("完成",null).setNeutralButton("系统通知设置",(d,w)->activity.startActivity(new Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE,activity.getPackageName()))).show();
    }
    void permissionResult(boolean granted){if(granted)setEnabled(true);else status="系统通知未授权，请在系统设置中允许。";}
    private void setEnabled(boolean value){
        preferences.edit().putBoolean("enabled",value).apply();epoch++;busy=false;status=value?"正在连接通知服务…":"通知已关闭";
        if(value){VivoPushBridge.enable(activity);tick();}else{VivoPushBridge.disable(activity);activity.getSystemService(NotificationManager.class).cancelAll();var api=session.searchClient();if(api!=null)worker.execute(()->{try{api.removeNotifications(session.deviceId);}catch(Exception ignored){}});}
    }
    void open(Intent intent){
        if(intent==null||!intent.hasExtra("accountId")||!session.configured())return;
        String account=intent.getStringExtra("accountId"),room=intent.getStringExtra("roomId");long message=intent.getLongExtra("messageId",0);intent.removeExtra("accountId");
        if(!session.user.id().equals(account)||room==null||message<=0)return;var api=session.searchClient();int connection=session.connectionStamp();
        worker.execute(()->{try{api.searchContext(room,message,"around");main.post(()->{if(connection==session.connectionStamp())openRoom.accept(room);});}catch(Exception e){main.post(()->{if(connection==session.connectionStamp())session.report(e);});}});
    }
    static void channel(Context context){NotificationChannel channel=new NotificationChannel(CHANNEL,"聊天消息",NotificationManager.IMPORTANCE_DEFAULT);channel.setDescription("Agent 回复和其他成员的新消息");context.getSystemService(NotificationManager.class).createNotificationChannel(channel);}
    static void notify(Context context,String account,String room,long message,String title,String body){
        var prefs=context.getSharedPreferences("notifications",Context.MODE_PRIVATE);if(!prefs.getBoolean("enabled",false)||!account.equals(prefs.getString("account","")))return;
        if(Build.VERSION.SDK_INT>=33&&context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)return;
        channel(context);Intent intent=new Intent(context,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP).setData(Uri.parse("leon-notification://message/"+message)).putExtra("accountId",account).putExtra("roomId",room).putExtra("messageId",message);
        var pending=PendingIntent.getActivity(context,0,intent,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        var notification=new Notification.Builder(context,CHANNEL).setSmallIcon(R.drawable.ic_notification).setContentTitle(title).setContentText(body).setStyle(new Notification.BigTextStyle().bigText(body)).setAutoCancel(true).setCategory(Notification.CATEGORY_MESSAGE).setVisibility(Notification.VISIBILITY_PRIVATE).setContentIntent(pending).setGroup("leon:"+account+":"+room).build();
        context.getSystemService(NotificationManager.class).notify("leon:"+account,(int)(message^(message>>>32)),notification);
    }
}
