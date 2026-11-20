package com.leon.app;

import android.app.*;
import android.content.*;
import android.net.Uri;
import android.text.InputType;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.function.Consumer;
import java.util.zip.ZipInputStream;

/** Native chat commands. File access always uses the system document picker. */
final class ChatTools {
    static final int SAVE_BACKUP=71,LOAD_BACKUP=72;
    private final Activity activity;
    private final ChatSession session;
    private final Consumer<MessageApi.Conversation> openRoom;
    private AlertDialog dialog;
    ChatTools(Activity activity,ChatSession session,Consumer<MessageApi.Conversation> openRoom){this.activity=activity;this.session=session;this.openRoom=openRoom;}
    void close(){if(dialog!=null)dialog.dismiss();}
    void changed(){
        if(dialog!=null&&dialog.isShowing()&&dialog.getButton(AlertDialog.BUTTON_POSITIVE)!=null){
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(!session.toolsBusy);
            if(!session.toolsBusy&&dialog.getButton(AlertDialog.BUTTON_NEGATIVE)!=null){dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setEnabled(true);dialog.setCancelable(true);}
        }
    }
    private boolean live(){return !activity.isFinishing()&&!activity.isDestroyed();}
    private boolean ready(){
        if(!session.configured()){toast("请先连接服务器");return false;}
        if(session.configuring||session.toolsBusy||session.openingConversation()){toast("请等待当前操作完成");return false;}
        return true;
    }
    private void toast(String message){if(live())Toast.makeText(activity,message,Toast.LENGTH_LONG).show();}
    private void show(AlertDialog next){if(!live())return;close();dialog=next;dialog.show();changed();}
    private JSONObject body(String room)throws JSONException{return new JSONObject().put("conversationId",room);}
    private void chooseAgent(Consumer<MessageApi.Agent> action){
        var available=session.availableAgents();
        if(session.selected()!=null&&session.selected().kind.equals("direct")){
            for(var agent:session.agents)if(agent.id.equals(session.selected().agentId)){action.accept(agent);return;}
        }
        if(available.isEmpty()){toast("当前会话没有可用 Agent");return;}
        String[] labels=new String[available.size()];for(int i=0;i<labels.length;i++)labels[i]=available.get(i).name;
        show(new AlertDialog.Builder(activity).setTitle("选择 Agent").setItems(labels,(d,i)->action.accept(available.get(i))).setNegativeButton("取消",null).create());
    }
    void context(){
        if(!ready())return;String room=session.selectedConversation;
        session.tool("正在读取上下文…",api->api.context(room),info->{
            if(!live())return;
            LinearLayout content=new LinearLayout(activity);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(30,16,30,16);
            TextView label=new TextView(activity);label.setText("token".equals(info.optString("compressionMode"))?"按 Token 预算管理上下文，不再按对话轮数自动压缩。":"当前服务端尚未提供新版记忆策略，请升级服务端。");content.addView(label);
            StringBuilder detail=new StringBuilder("输入预算：").append(info.optInt("inputTokenBudget")).append(" Token\n");
            JSONArray agents=info.optJSONArray("agents");
            if(agents!=null)for(int i=0;i<agents.length();i++){
                JSONObject agent=agents.optJSONObject(i);if(agent==null)continue;
                detail.append("\n").append(agent.optString("agentName")).append("\n最近请求约 ").append(agent.optInt("estimatedInputTokens")).append(" Token · ").append(agent.optInt("retainedRounds")).append(" 轮\n");
                if(agent.optInt("retrievedRounds")>0)detail.append("检索相关历史原文：").append(agent.optInt("retrievedRounds")).append(" 轮\n");
                if(agent.optBoolean("compressionFallback"))detail.append("最近请求使用了完整原文回退\n");
                detail.append("已确认事实：\n");JSONArray facts=agent.optJSONArray("facts");
                if(facts==null||facts.length()==0)detail.append("压缩时提取有用户原文依据的事实。\n");
                if(facts!=null)for(int f=0;f<facts.length();f++){JSONObject fact=facts.optJSONObject(f);if(fact!=null)detail.append(fact.optString("speaker")).append("：").append(fact.optString("value")).append(" · 来源 #").append(fact.optLong("sourceMessageId")).append("\n");}
                String summary=agent.optString("summary");detail.append("阶段摘要：\n").append(summary.isEmpty()?"尚无压缩摘要":summary).append("\n");
            }
            TextView summary=new TextView(activity);summary.setText(detail);summary.setTextIsSelectable(true);content.addView(summary);
            ScrollView scroll=new ScrollView(activity);scroll.addView(content);
            show(new AlertDialog.Builder(activity).setTitle("查看上下文").setView(scroll).setNegativeButton("关闭",null).setNeutralButton("刷新",(d,w)->context()).create());
        });
    }
    void compact(){
        if(!ready())return;String room=session.selectedConversation;
        chooseAgent(agent->session.tool("正在提交压缩…",api->api.contextAction("compact",body(room).put("agentId",agent.id).put("requestId",UUID.randomUUID().toString())),result->{toast("已提交上下文压缩，完成后自动显示结果");session.refresh();}));
    }
    void clear(){
        if(!ready()||!canClear())return;String room=session.selectedConversation;
        session.tool("正在检查聊天记录…",api->api.clearPreview(room),preview->{
            if(!live())return;
            if(preview.optBoolean("hasActiveWork")){toast("请等待当前回复、压缩或总结完成后再清理");return;}
            String request=UUID.randomUUID().toString();
            AlertDialog next=new AlertDialog.Builder(activity).setTitle("清理聊天记录？")
                .setMessage("将永久删除「"+preview.optString("conversationName")+"」的 "+preview.optLong("messageCount")+" 条消息、图片与上下文，并同步至所有设备。可先备份，之后通过加载备份恢复为独立对话。")
                .setNegativeButton("取消",null).setNeutralButton("先备份",(d,w)->backup()).setPositiveButton("永久清理",null).create();
            show(next);next.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{
                if(!ready()||!canClear()||!room.equals(session.selectedConversation))return;
                session.tool("正在清理记录…",api->api.contextAction("clear",body(room).put("requestId",request).put("expectedLatestMessageId",preview.getLong("latestMessageId")).put("expectedHistoryRevision",preview.getLong("historyRevision")).put("confirm",true)),result->{
                    next.dismiss();session.clearLocalHistory(room,result.optLong("historyRevision"));toast("聊天记录已清理");
                });
            });
        });
    }
    private boolean canClear(){
        if(session.preparingImages>0||!session.sending.isEmpty()){toast("请等待图片处理及消息发送完成后再清理");return false;}return true;
    }
    void backup(){
        if(!ready())return;String room=session.selectedConversation;int connection=session.connectionStamp();
        session.tool("正在生成完整备份…",api->{
            byte[] bytes=api.backup(room);File file=File.createTempFile("leon-chat-",".zip",activity.getCacheDir());
            try(var out=new FileOutputStream(file)){out.write(bytes);}catch(Exception failure){file.delete();throw failure;}
            return file;
        },file->{
            if(!live()){file.delete();return;}
            if(session.pendingBackup!=null)session.pendingBackup.delete();session.pendingBackup=file;session.pendingBackupConnection=connection;
            Intent picker=new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("application/zip").addCategory(Intent.CATEGORY_OPENABLE);
            picker.putExtra(Intent.EXTRA_TITLE,"Leon-聊天备份-"+new SimpleDateFormat("yyyyMMdd-HHmmss",Locale.CHINA).format(new Date())+".zip");
            activity.startActivityForResult(picker,SAVE_BACKUP);
        });
    }
    void load(){
        if(!ready())return;
        session.pendingImportConnection=session.connectionStamp();session.pendingImportAgent=session.selected()!=null&&session.selected().kind.equals("direct")?session.selected().agentId:"";
        activity.startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("application/zip").addCategory(Intent.CATEGORY_OPENABLE),LOAD_BACKUP);
    }
    boolean result(int code,int result,Intent data){
        if(code!=SAVE_BACKUP&&code!=LOAD_BACKUP)return false;
        if(result!=Activity.RESULT_OK||data==null||data.getData()==null){if(code==SAVE_BACKUP)discardBackup();return true;}
        Uri uri=data.getData();
        if(code==SAVE_BACKUP){
            File file=session.pendingBackup;
            if(file==null||!file.isFile()){toast("备份已失效，请重新备份");return true;}
            if(session.pendingBackupConnection!=session.connectionStamp()){discardBackup();toast("连接已切换，请重新备份");return true;}
            session.tool("正在保存备份…",api->{
                try(var in=new FileInputStream(file);var out=activity.getContentResolver().openOutputStream(uri,"wt")){
                    if(out==null)throw new IOException("无法写入所选位置");byte[] buffer=new byte[8192];for(int n;(n=in.read(buffer))!=-1;)out.write(buffer,0,n);
                }return true;
            },saved->{discardBackup();toast("聊天备份已保存，文件包含聊天内容及图片，请妥善保管");});
        }else {
            if(session.pendingImportConnection!=session.connectionStamp()){toast("连接已切换，请重新选择备份");return true;}
            String target=session.pendingImportAgent;
            session.tool("正在读取备份…",api->{
                byte[] bytes;
                try(var in=activity.getContentResolver().openInputStream(uri)){if(in==null)throw new IOException("无法读取备份");bytes=readLimited(in,MessageApi.MAX_BACKUP+1);}
                if(bytes.length>MessageApi.MAX_BACKUP)throw new IOException("备份不能超过 32 MB");
                JSONObject manifest;
                try(var zip=new ZipInputStream(new ByteArrayInputStream(bytes))){
                    var first=zip.getNextEntry();if(first==null||!first.getName().equals("manifest.json"))throw new IOException("不是 Leon 聊天备份");
                    byte[] metadata=readLimited(zip,16*1024*1024+1);if(metadata.length>16*1024*1024)throw new IOException("备份内容过大");
                    manifest=new JSONObject(new String(metadata,java.nio.charset.StandardCharsets.UTF_8));
                }
                if(!manifest.optString("format").equals("leon-chat")||(manifest.optInt("version")!=1&&manifest.optInt("version")!=2))throw new IOException("不支持此备份格式");
                return new ImportFile(bytes,manifest);
            },file->confirmImport(file,target));
        }return true;
    }
    static byte[] readLimited(InputStream in,int limit)throws IOException{
        var out=new ByteArrayOutputStream();byte[] buffer=new byte[8192];
        while(out.size()<limit){int n=in.read(buffer,0,Math.min(buffer.length,limit-out.size()));if(n==-1)break;out.write(buffer,0,n);}
        return out.toByteArray();
    }
    private record ImportFile(byte[] bytes,JSONObject manifest){}
    private void confirmImport(ImportFile file,String target){
        if(!live())return;JSONObject room=file.manifest.optJSONObject("conversation");JSONArray messages=file.manifest.optJSONArray("messages");
        if(room==null||messages==null){toast("备份缺少聊天内容");return;}
        if(!target.isEmpty()&&!room.optString("kind").equals("direct")){toast("群聊备份请从群聊页面加载");return;}
        String request=UUID.randomUUID().toString();
        AlertDialog next=new AlertDialog.Builder(activity).setTitle("加载聊天备份")
            .setMessage("「"+room.optString("name")+"」\n"+messages.length()+" 条消息\n\n将恢复文字、图片和上下文，创建独立对话；已有记录不会被覆盖，也不会自动调用模型。")
            .setNegativeButton("取消",null).setPositiveButton("加载为新对话",null).create();
        show(next);next.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{
            if(!ready())return;
            session.tool("正在加载备份…",api->api.restoreBackup(file.bytes,request,target),restored->{next.dismiss();session.addConversation(restored);if(live())openRoom.accept(restored);toast("备份已加载");});
        });
    }
    private void discardBackup(){if(session.pendingBackup!=null)session.pendingBackup.delete();session.pendingBackup=null;}
    void branch(MessageApi.Message message){
        if(!ready()||message.id<=0||!session.selectedConversation.equals(message.conversationId))return;
        String source=message.conversationId;int connection=session.connectionStamp();String request=UUID.randomUUID().toString();
        EditText name=new EditText(activity);name.setSingleLine();name.setInputType(InputType.TYPE_CLASS_TEXT);
        String title=session.title();int end=Math.min(50,title.length());if(end>0&&Character.isHighSurrogate(title.charAt(end-1)))end--;
        name.setText(title.substring(0,end)+" · 分支");name.setTag("branch_name");
        String note="复制到这条消息（含）为止的记录，在新会话中继续独立讨论。";
        if(session.selected()!=null&&session.selected().kind.equals("group"))note+="\n群聊分支仅自己可见，保留原 Agent，可再邀请其他用户。";
        AlertDialog next=new AlertDialog.Builder(activity).setTitle("创建对话分支").setMessage(note).setView(name).setNegativeButton("取消",null).setPositiveButton("创建分支",null).create();
        String[] submitted={null};show(next);
        next.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{
            if(!ready())return;
            if(connection!=session.connectionStamp()||!source.equals(session.selectedConversation)){next.dismiss();return;}
            String value=submitted[0]==null?name.getText().toString().trim():submitted[0];
            if(value.isEmpty()||value.length()>60){name.setError("名称应为 1–60 字");return;}
            submitted[0]=value;name.setEnabled(false);
            next.setCancelable(false);next.getButton(AlertDialog.BUTTON_NEGATIVE).setEnabled(false);
            session.tool("正在创建分支…",api->api.branch(source,message.id,request,value),room->{
                next.dismiss();session.addConversation(room);if(live())openRoom.accept(room);
            });
        });
    }
    void newConversation(){
        if(!ready())return;
        chooseAgent(this::newConversation);
    }
    void newConversation(MessageApi.Agent agent){
        if(!ready())return;
        EditText name=new EditText(activity);name.setSingleLine();name.setInputType(InputType.TYPE_CLASS_TEXT);String defaultName="新对话 · "+new SimpleDateFormat("MM-dd HH:mm",Locale.CHINA).format(new Date());name.setText(defaultName);
        String request=UUID.randomUUID().toString();
        AlertDialog next=new AlertDialog.Builder(activity).setTitle("与 "+agent.name+" 新建对话")
            .setMessage("新对话将从空白开始，不携带当前对话的消息和上下文。原对话可从 Agent 主页查看。")
            .setView(name).setNegativeButton("取消",null).setPositiveButton("创建",null).create();
        show(next);next.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{
            if(!ready())return;String title=name.getText().toString().trim();if(title.isEmpty()||title.length()>60){name.setError("名称应为 1–60 字");return;}
            session.tool("正在新建对话…",api->api.newThread(agent.id,request,title),room->{next.dismiss();session.addConversation(room);if(live())openRoom.accept(room);});
        });
    }
}
