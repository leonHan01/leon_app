package com.leon.app;

import android.app.*;
import android.content.*;
import android.net.Uri;
import android.os.*;
import android.graphics.Color;
import android.view.*;
import android.widget.*;
import androidx.core.content.FileProvider;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;

final class ChatDocuments {
    static final int PICK=46,SAVE=47;
    private final Activity activity;private final ChatSession session;private final ChatUi ui;
    private final Handler main=new Handler(Looper.getMainLooper());private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private File export;private int exportConnection;
    ChatDocuments(Activity activity,ChatSession session){this.activity=activity;this.session=session;ui=new ChatUi(activity);}
    void choose(){
        if(!session.configured())return;session.documentPickerRoom=session.selectedConversation;session.documentPickerConnection=session.connectionStamp();
        Intent picker=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true);
        picker.putExtra(Intent.EXTRA_MIME_TYPES,new String[]{"application/pdf","text/plain","application/msword","application/vnd.openxmlformats-officedocument.wordprocessingml.document","application/vnd.ms-excel","application/vnd.openxmlformats-officedocument.spreadsheetml.sheet","text/markdown","text/csv","text/comma-separated-values","application/octet-stream"});
        activity.startActivityForResult(picker,PICK);
    }
    boolean result(int request,int result,Intent data){
        if(request==PICK){if(result==Activity.RESULT_OK&&data!=null){List<Uri> uris=new ArrayList<>();if(data.getClipData()!=null){for(int i=0;i<data.getClipData().getItemCount();i++)uris.add(data.getClipData().getItemAt(i).getUri());}else if(data.getData()!=null)uris.add(data.getData());session.addDocuments(uris,session.documentPickerRoom,session.documentPickerConnection);}session.documentPickerRoom="";return true;}
        if(request==SAVE&&export!=null){if(result==Activity.RESULT_OK&&data!=null&&data.getData()!=null&&export!=null){File source=export;export=null;Uri target=data.getData();int connection=exportConnection;
            worker.execute(()->{try(var input=new FileInputStream(source);var output=activity.getContentResolver().openOutputStream(target)){if(output==null)throw new IOException("无法写入所选位置。");byte[] buffer=new byte[65536];for(int count;(count=input.read(buffer))!=-1;)output.write(buffer,0,count);main.post(()->{if(connection==session.connectionStamp())Toast.makeText(activity,"文件已保存",Toast.LENGTH_SHORT).show();});}catch(Exception e){main.post(()->{if(connection==session.connectionStamp())session.report(e);});}});}export=null;return true;}return false;
    }
    View card(ChatDocument doc,Long favorite,Runnable remove,Runnable actions){
        LinearLayout row=new LinearLayout(activity);row.setOrientation(LinearLayout.HORIZONTAL);row.setGravity(Gravity.CENTER_VERTICAL);row.setPadding(ui.dp(12),ui.dp(9),ui.dp(12),ui.dp(9));row.setBackground(ui.shape(ChatUi.BAR,7));
        ImageView icon=new ImageView(activity);icon.setImageResource(R.drawable.ic_document);row.addView(icon,new LinearLayout.LayoutParams(ui.dp(28),ui.dp(32)));
        LinearLayout labels=new LinearLayout(activity);labels.setOrientation(LinearLayout.VERTICAL);labels.setPadding(ui.dp(10),0,ui.dp(8),0);TextView title=ui.text(doc.name,14,Color.BLACK);title.setMaxLines(2);labels.addView(title);labels.addView(ui.text(doc.detail(),11,Color.BLACK));row.addView(labels,new LinearLayout.LayoutParams(0,-2,1));
        if(remove!=null){Button cancel=ui.button("×");cancel.setTextColor(Color.BLACK);cancel.setContentDescription("移除附件");cancel.setOnClickListener(v->remove.run());row.addView(cancel,new LinearLayout.LayoutParams(ui.dp(44),ui.dp(44)));}
        else{row.setOnClickListener(v->open(doc,favorite));if(actions!=null)row.setOnLongClickListener(v->{actions.run();return true;});}
        row.setTag("document:"+doc.id);return row;
    }
    private void open(ChatDocument doc,Long favorite){
        var api=session.searchClient();if(api==null)return;int connection=session.connectionStamp();Toast.makeText(activity,"正在读取文件…",Toast.LENGTH_SHORT).show();
        worker.execute(()->{try{
            byte[] bytes=api.document(doc.id,favorite);File folder=new File(activity.getCacheDir(),"document-previews/"+UUID.randomUUID());if(!folder.mkdirs())throw new IOException("无法保存文件预览。");
            File file=new File(folder,new File(doc.name).getName());try(var output=new FileOutputStream(file)){output.write(bytes);}
            main.post(()->{if(connection!=session.connectionStamp()||activity.isDestroyed())return;new AlertDialog.Builder(activity).setTitle(doc.name).setItems(new String[]{"打开文件","保存到文件"},(d,which)->{if(which==1){save(file,doc,connection);return;}try{
                Uri uri=FileProvider.getUriForFile(activity,activity.getPackageName()+".documents",file);Intent intent=new Intent(Intent.ACTION_VIEW).setDataAndType(uri,mime(doc.name)).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);activity.startActivity(intent);
            }catch(ActivityNotFoundException missing){save(file,doc,connection);}}).setNegativeButton("取消",null).show();});
        }catch(Exception e){main.post(()->{if(connection==session.connectionStamp()){session.searchFailure(e);session.report(e);}});}});
    }
    private void save(File file,ChatDocument doc,int connection){export=file;exportConnection=connection;activity.startActivityForResult(new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(mime(doc.name)).putExtra(Intent.EXTRA_TITLE,doc.name),SAVE);}
    private static String mime(String name){String ext=name.substring(name.lastIndexOf('.')+1).toLowerCase(Locale.ROOT);String type=android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);return type==null?"application/octet-stream":type;}
    void close(){worker.shutdownNow();}
}
